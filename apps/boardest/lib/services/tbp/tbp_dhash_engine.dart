import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// JS 기반 perceptual dHash 엔진 (DOM + URL Hash)
/// - JS 스크립트 주입으로 256-bit dHash 계산 결과를 webMessage/JavaScriptChannel로 수신
/// - 지수 버스트 폴링 (0, 215, 462, 994, 2137, 4594, 9877 ms)
/// - 5초 포커스 폴링 + 12초 메인 폴백 폴링
class TbpDhashEngine {
  final Function(String dHash) onDhashChanged;

  TbpDhashEngine({required this.onDhashChanged});

  WebviewController? _winController;
  WebViewController? _androidController;

  String _currentDhash = '';
  Timer? _focusPollingTimer;
  Timer? _fallbackPollingTimer;
  final List<Timer> _burstTimers = [];
  bool _disposed = false;

  // boadbook 동일 지수 버스트 딜레이 (ms): 2.15^n * 100
  static const List<int> _burstDelaysMs = [0, 215, 462, 994, 2137, 4594, 9877];

  // Hamming distance 매칭 임계값
  static const int _matchThreshold = 64;
  // 노이즈 필터 (이 미만 차이면 무시)
  static const int _noiseFilterBits = 3;

  /// JS 해시 추출 스크립트
  static const String _hashJsScript = '''
    (function() {
      function sendHash(hashStr) {
        var msg = JSON.stringify({type: 'dhashResult', hash: hashStr});
        if (window.chrome && window.chrome.webview) {
          window.chrome.webview.postMessage(msg);
        }
        if (window.TbpChannel && window.TbpChannel.postMessage) {
          window.TbpChannel.postMessage(msg);
        }
      }

      function computeDhash(canvas) {
        var ctx = canvas.getContext('2d');
        var w = canvas.width;
        var h = canvas.height;
        var size = Math.min(w, h);
        var sx = (w - size) / 2;
        var sy = (h - size) / 2;
        
        var offscreen = document.createElement('canvas');
        offscreen.width = 17;
        offscreen.height = 16;
        var octx = offscreen.getContext('2d');
        octx.drawImage(canvas, sx, sy, size, size, 0, 0, 17, 16);
        
        var imgData = octx.getImageData(0, 0, 17, 16).data;
        var gray = [];
        for (var i = 0; i < imgData.length; i += 4) {
          gray.push(imgData[i] * 0.299 + imgData[i+1] * 0.587 + imgData[i+2] * 0.114);
        }
        
        var hash = '';
        for (var y = 0; y < 16; y++) {
          for (var x = 0; x < 16; x++) {
            var idx = y * 17 + x;
            hash += (gray[idx] > gray[idx + 1] ? '1' : '0');
          }
        }
        sendHash(hash);
      }

      try {
        if (typeof html2canvas === 'undefined') {
          var script = document.createElement('script');
          script.src = 'https://html2canvas.hertzen.com/dist/html2canvas.min.js';
          script.onload = function() {
            html2canvas(document.body).then(computeDhash).catch(function(e){ sendHash(null); });
          };
          script.onerror = function() { sendHash(null); };
          document.head.appendChild(script);
        } else {
          html2canvas(document.body).then(computeDhash).catch(function(e){ sendHash(null); });
        }
      } catch(e) {
        sendHash(null);
      }
    })();
  ''';

  /// 컨트롤러 설정 + 배경 폴링 시작
  void startTracker(WebviewController? winController, WebViewController? androidController) {
    _winController = winController;
    _androidController = androidController;
    _startBackgroundPolling();
    // 초기 dHash 획득 (2초 후)
    Future.delayed(const Duration(seconds: 2), () {
      if (!_disposed) _triggerBurstCapture();
    });
  }

  /// WebView에서 수신된 JS 메시지 처리 (viewer route에서 호출)
  void onDhashMessage(String rawMessage) {
    try {
      final data = jsonDecode(rawMessage);
      if (data is Map && data['type'] == 'dhashResult') {
        final hash = data['hash'] as String?;
        if (hash != null && hash.isNotEmpty) {
          _onNewHash(hash);
        }
      }
    } catch (e) {
      // 다른 유형 메시지 무시
    }
  }

  /// 페이지 이동 (ArrowRight / ArrowLeft)
  Future<void> navigatePage({required bool isNext}) async {
    final key = isNext ? 'ArrowRight' : 'ArrowLeft';
    final keyCode = isNext ? 39 : 37;

    final script = '''
      (function() {
        var el = document.activeElement || document.body;
        ['keydown','keyup'].forEach(function(type) {
          el.dispatchEvent(new KeyboardEvent(type, {
            bubbles: true, cancelable: true,
            key: '$key', code: '${isNext ? 'ArrowRight' : 'ArrowLeft'}',
            keyCode: $keyCode, which: $keyCode
          }));
        });
      })();
    ''';

    await _executeScript(script);
    _triggerBurstCapture();
  }

  // ─── 내부 구현 ─────────────────────────────────────────────

  void _startBackgroundPolling() {
    // 5초 포커스 폴링
    _focusPollingTimer?.cancel();
    _focusPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_disposed) _requestHashFromJs();
    });

    // 12초 메인 폴백 폴링
    _fallbackPollingTimer?.cancel();
    _fallbackPollingTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!_disposed) _requestHashFromJs();
    });
  }

  /// boadbook 동일 지수 버스트 캡처
  void _triggerBurstCapture() {
    // 기존 버스트 타이머 취소
    for (final t in _burstTimers) t.cancel();
    _burstTimers.clear();

    for (final ms in _burstDelaysMs) {
      final t = Timer(Duration(milliseconds: ms), () {
        if (!_disposed) _requestHashFromJs();
      });
      _burstTimers.add(t);
    }
  }

  void requestHashNow() {
    if (!_disposed) {
      _requestHashFromJs();
    }
  }

  Future<void> _requestHashFromJs() async {
    await _executeScript(_hashJsScript);
  }

  void _onNewHash(String newHash) {
    if (_currentDhash.isEmpty) {
      _currentDhash = newHash;
      onDhashChanged(newHash);
      return;
    }

    final dist = _hammingDistance(_currentDhash, newHash);

    // 노이즈 및 동일 페이지 매칭 범위 (<= 64비트): 같은 페이지로 간주하여 불필요한 재로드 차단
    if (dist <= _matchThreshold) {
      return;
    }

    // 64비트 초과: 완전히 다른 새로운 페이지로 전환
    _currentDhash = newHash;
    onDhashChanged(newHash);
  }

  Future<void> _executeScript(String script) async {
    try {
      if (Platform.isWindows && _winController != null) {
        await _winController!.executeScript(script);
      } else if (!Platform.isWindows && _androidController != null) {
        await _androidController!.runJavaScript(script);
      }
    } catch (e) {
      debugPrint('[TbpDhash] Script error: $e');
    }
  }

  void dispose() {
    _disposed = true;
    _focusPollingTimer?.cancel();
    _fallbackPollingTimer?.cancel();
    for (final t in _burstTimers) t.cancel();
    _burstTimers.clear();
  }

  /// Hamming distance (서로 다른 비트 수 계산)
  int _hammingDistance(String a, String b) {
    if (a.length != b.length) return 256;
    int dist = 0;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) dist++;
    }
    return dist;
  }
}
