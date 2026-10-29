import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'tbp_storage_service.dart';
import 'tbp_web_capture_helper.dart';

/// JS 기반 perceptual dHash 엔진 (Visual Canvas + DOM Page Fingerprint + Canonical Hash Matching)
/// - 페이지 이동 시 실시간으로 256-bit dHash를 감지하고 기존 저장된 페이지 해시와 해밍 거리(<=36bit)로 매칭
/// - 동일 페이지 내 미세 노이즈(<=32bit)는 무시하여 판서와 핫스팟이 흔들림 없이 유지됨
/// - 마우스 모드에서 WebView 내부 우클릭 및 길게 누르기(Long-Press) 이벤트를 감지하여 핫스팟 모달 호출 지원
class TbpDhashEngine {
  final Function(String dHash) onDhashChanged;
  final Function(double rx, double ry)? onWebContextMenu;

  TbpDhashEngine({
    required this.onDhashChanged,
    this.onWebContextMenu,
  });

  WebviewController? _winController;
  WebViewController? _androidController;

  String _currentDhash = '';
  final Set<String> _knownHashes = {};
  int _webVirtualPage = 1;

  Timer? _focusPollingTimer;
  Timer? _fallbackPollingTimer;
  final List<Timer> _burstTimers = [];
  bool _disposed = false;

  // 지수 버스트 딜레이 (ms): 페이지 넘김 직후 즉각 감지
  static const List<int> _burstDelaysMs = [0, 1000, 2000, 5000];

  // 동일 페이지 판정 임계값 (민감도 대폭 상향: 14비트 이하 차이만 동일 페이지 노이즈로 간주하고, 미세한 페이지 전환도 즉시 감지)
  static const int _samePageThreshold = 14;
  // 기존 저장된 페이지 해시와 매칭할 임계값 (18비트 이하 차이면 저장된 페이지 해시로 정밀 스냅)
  static const int _knownMatchThreshold = 18;

  /// 기존 저장된 페이지 dHash 목록을 등록하여 페이지 재방문 시 판서/핫스팟 100% 복원 보장
  void registerKnownHashes(Iterable<String> hashes) {
    for (final h in hashes) {
      if (h.isNotEmpty && h != 'default') {
        _knownHashes.add(TbpStorageService.toBinary256(h) ?? h);
      }
    }
  }

  /// JS 해시 추출 및 이벤트 후킹 스크립트
  static const String _hashJsScript = '''
    (function() {
      // ── [FHD 125% 표준 뷰포트 강제 락 (모든 기기/배율/해상도 편차 완전 제거)] ──
      try {
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.name = 'viewport';
          document.head.appendChild(meta);
        }
        // 1920 / 1.25 = 1536px 논리 해상도 고정
        meta.content = 'width=1536, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';

        var styleId = 'bst-fhd-lock-style';
        var styleEl = document.getElementById(styleId);
        if (!styleEl) {
          styleEl = document.createElement('style');
          styleEl.id = styleId;
          document.head.appendChild(styleEl);
        }
        styleEl.textContent = 'html, body { width: 1536px !important; min-width: 1536px !important; margin: 0 auto !important; text-size-adjust: 100% !important; -webkit-text-size-adjust: 100% !important; }';
      } catch (ve) {}

      function postToFlutter(payload) {
        var msg = JSON.stringify(payload);
        if (window.chrome && window.chrome.webview) {
          window.chrome.webview.postMessage(msg);
        }
        if (window.TbpChannel && window.TbpChannel.postMessage) {
          window.TbpChannel.postMessage(msg);
        }
      }

      function sendHash(hashStr) {
        if (!hashStr) return;
        postToFlutter({type: 'dhashResult', hash: hashStr});
      }

      // 1회성: WebView 내부 우클릭(contextmenu) 및 길게 누르기(Long-Press) 감지 + 페이지 변화 즉시 감지 훅 설치
      function bindDocEvents(doc, win, offsetLeft, offsetTop) {
        if (!doc || doc.__bstBound) return;
        doc.__bstBound = true;

        doc.addEventListener('contextmenu', function(e) {
          e.preventDefault();
          e.stopPropagation();
          var vw = window.innerWidth || document.documentElement.clientWidth || 1;
          var vh = window.innerHeight || document.documentElement.clientHeight || 1;
          var cx = (e.clientX || 0) + (offsetLeft || 0);
          var cy = (e.clientY || 0) + (offsetTop || 0);
          postToFlutter({
            type: 'hotspotContext',
            rx: Math.max(0.02, Math.min(0.98, cx / vw)),
            ry: Math.max(0.02, Math.min(0.98, cy / vh))
          });
          return false;
        }, true);

        var lpTimer = null;
        var startX = 0;
        var startY = 0;
        doc.addEventListener('pointerdown', function(e) {
          if (e.button === 2) return;
          startX = e.clientX || 0;
          startY = e.clientY || 0;
          if (lpTimer) clearTimeout(lpTimer);
          lpTimer = setTimeout(function() {
            var vw = window.innerWidth || document.documentElement.clientWidth || 1;
            var vh = window.innerHeight || document.documentElement.clientHeight || 1;
            var cx = startX + (offsetLeft || 0);
            var cy = startY + (offsetTop || 0);
            postToFlutter({
              type: 'hotspotContext',
              rx: Math.max(0.02, Math.min(0.98, cx / vw)),
              ry: Math.max(0.02, Math.min(0.98, cy / vh))
            });
          }, 650);
        }, true);

        doc.addEventListener('pointermove', function(e) {
          if (!lpTimer) return;
          var dx = (e.clientX || 0) - startX;
          var dy = (e.clientY || 0) - startY;
          if (Math.sqrt(dx * dx + dy * dy) > 10) {
            clearTimeout(lpTimer);
            lpTimer = null;
          }
        }, true);

        var clearLp = function() {
          if (lpTimer) {
            clearTimeout(lpTimer);
            lpTimer = null;
          }
        };
        doc.addEventListener('pointerup', clearLp, true);
        doc.addEventListener('pointercancel', clearLp, true);

        doc.addEventListener('click', function() {
          setTimeout(runCapture, 120);
          setTimeout(runCapture, 450);
        }, true);
        doc.addEventListener('keyup', function() {
          setTimeout(runCapture, 120);
          setTimeout(runCapture, 450);
        }, true);
      }

      try {
        bindDocEvents(document, window, 0, 0);
        var frames = document.querySelectorAll('iframe');
        for (var fi = 0; fi < frames.length; fi++) {
          try {
            var fr = frames[fi];
            var rect = fr.getBoundingClientRect();
            if (fr.contentDocument && fr.contentWindow) {
              bindDocEvents(fr.contentDocument, fr.contentWindow, rect.left, rect.top);
            }
          } catch (ie) {}
        }
      } catch (be) {}

      function computeDhashFromSource(sourceEl, w, h) {
        try {
          if (!w || !h || w < 32 || h < 32) return false;

          // 16:9 표준 뷰포트 종횡비에 맞춰 다운샘플링 (모든 기기 해상도 편차 평탄화)
          var offscreen = document.createElement('canvas');
          offscreen.width = 17;
          offscreen.height = 16;
          var octx = offscreen.getContext('2d');
          octx.imageSmoothingEnabled = true;
          octx.imageSmoothingQuality = 'medium';
          octx.drawImage(sourceEl, 0, 0, w, h, 0, 0, 17, 16);

          var imgData = octx.getImageData(0, 0, 17, 16).data;
          var gray = [];
          var nonZero = 0;
          for (var i = 0; i < imgData.length; i += 4) {
            var g = imgData[i] * 0.299 + imgData[i+1] * 0.587 + imgData[i+2] * 0.114;
            if (g > 1 && g < 254) nonZero++;
            gray.push(g);
          }
          // 완전히 단색(빈 캔버스)이면 폴백 사용
          if (nonZero < 8) return false;

          var hash = '';
          for (var y = 0; y < 16; y++) {
            for (var x = 0; x < 16; x++) {
              var idx = y * 17 + x;
              hash += (gray[idx] > gray[idx + 1] ? '1' : '0');
            }
          }
          sendHash(hash);
          return true;
        } catch (e) {
          return false;
        }
      }

      function collectDocSignature(doc, win) {
        if (!doc) return '';
        var parts = [];
        try {
          parts.push(win && win.location ? win.location.href : '');
          // 페이지 번호 입력창/표시 요소 우선 추출 (전자교과서/뷰어 표준 패턴)
          var pageInputs = doc.querySelectorAll('input[type="text"], input[type="number"], .page, .pageNum, .page-num, .current-page, [class*="page"], [id*="page"], [aria-current="page"], [aria-selected="true"]');
          var pageVals = [];
          for (var i = 0; i < Math.min(pageInputs.length, 20); i++) {
            var el = pageInputs[i];
            var v = (el.value !== undefined && el.value !== '') ? ('val:' + el.value) : (el.innerText || el.textContent || '').trim();
            if (v && v.length < 40) pageVals.push(v);
          }
          parts.push('PV:' + pageVals.join(','));

          // 현재 보이는 주요 이미지 src 및 위치
          var imgs = doc.images || [];
          var imgSigs = [];
          for (var j = 0; j < Math.min(imgs.length, 15); j++) {
            var im = imgs[j];
            var r = im.getBoundingClientRect ? im.getBoundingClientRect() : {width: im.width, height: im.height};
            if (r.width > 40 && r.height > 40) {
              imgSigs.push((im.currentSrc || im.src || '') + '@' + Math.round(r.left) + ',' + Math.round(r.top));
            }
          }
          parts.push('IM:' + imgSigs.join('|'));

          // 본문 가시 텍스트 요약
          var bodyTxt = (doc.body && doc.body.innerText) ? doc.body.innerText.replace(/\\s+/g, ' ').trim().slice(0, 600) : '';
          parts.push('TX:' + bodyTxt);
          parts.push('SC:' + Math.round(((win && win.scrollY) || 0) / 80));
        } catch (e) {}
        return parts.join('||');
      }

      function computeOfflineFallbackHash() {
        try {
          var sig = collectDocSignature(document, window);
          var frames = document.querySelectorAll('iframe');
          for (var f = 0; f < frames.length; f++) {
            try {
              var fr = frames[f];
              sig += '||FRSrc:' + (fr.src || '');
              if (fr.contentDocument && fr.contentWindow) {
                sig += '||FRDoc:' + collectDocSignature(fr.contentDocument, fr.contentWindow);
              }
            } catch (fe) {}
          }

          var bits = '';
          var seeds = [2166136261, 16777619, 2654435761, 3266489917, 668265263, 374761393, 2246822519, 3266489919];
          for (var s = 0; s < 8; s++) {
            var h = seeds[s] >>> 0;
            for (var i = 0; i < sig.length; i++) {
              h ^= sig.charCodeAt(i);
              h = Math.imul(h, 16777619) >>> 0;
            }
            bits += (h >>> 0).toString(2).padStart(32, '0');
          }
          sendHash(bits.slice(0, 256));
        } catch (err) {}
      }

      function tryDirectCanvasHash(doc) {
        if (!doc) return false;
        var canvases = doc.querySelectorAll('canvas');
        var bestCanvas = null;
        var bestArea = 0;
        for (var i = 0; i < canvases.length; i++) {
          var c = canvases[i];
          var r = c.getBoundingClientRect();
          var area = r.width * r.height;
          if (area > bestArea && r.width > 200 && r.height > 200) {
            bestArea = area;
            bestCanvas = c;
          }
        }
        if (bestCanvas && computeDhashFromSource(bestCanvas, bestCanvas.width, bestCanvas.height)) {
          return true;
        }
        return false;
      }

      function runCapture() {
        try {
          // 1. 페이지 내 대형 <canvas>(PDF.js/교과서 렌더러)가 있으면 즉시 픽셀 dHash 추출
          if (tryDirectCanvasHash(document)) return;
          var frames = document.querySelectorAll('iframe');
          for (var f = 0; f < frames.length; f++) {
            try {
              if (frames[f].contentDocument && tryDirectCanvasHash(frames[f].contentDocument)) return;
            } catch (e) {}
          }
          // 2. DOM + URL + 페이지번호 + 이미지 + 텍스트 기반 결정론적 256-bit 해시 추출 (빠르고 CSP/CORS 무관)
          computeOfflineFallbackHash();
        } catch (e) {
          computeOfflineFallbackHash();
        }
      }

      runCapture();
    })();
  ''';

  /// 컨트롤러 설정 + 배경 폴링 시작
  void startTracker(WebviewController? winController, WebViewController? androidController) {
    _winController = winController;
    _androidController = androidController;
    _startBackgroundPolling();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!_disposed) _triggerBurstCapture();
    });
  }

  /// Web 환경(cross-origin iframe)에서 가상 페이지 이동 시 페이지별 dHash 전환 지원
  void stepWebVirtualPage([int delta = 1, bool? isNext]) {
    if (!kIsWeb) return;
    final forward = isNext ?? (delta >= 0);
    if (forward) {
      _webVirtualPage++;
    } else if (_webVirtualPage > 1) {
      _webVirtualPage--;
    }
    final virtualHash = _webVirtualPage == 1 ? 'default' : 'web_page_$_webVirtualPage';
    if (_currentDhash != virtualHash) {
      _currentDhash = virtualHash;
      onDhashChanged(virtualHash);
    }
  }

  /// 외부(클릭 등)에서 버스트 캡처 트리거
  void triggerBurstCapture() => _triggerBurstCapture();

  /// WebView에서 수신된 JS 메시지 처리 (viewer route에서 호출)
  void onDhashMessage(String rawMessage) {
    try {
      final data = jsonDecode(rawMessage);
      if (data is Map) {
        if (data['type'] == 'dhashResult') {
          final hash = data['hash'] as String?;
          if (hash != null && hash.isNotEmpty) {
            _onNewHash(hash);
          }
        } else if (data['type'] == 'hotspotContext' && onWebContextMenu != null) {
          final rx = (data['rx'] as num?)?.toDouble();
          final ry = (data['ry'] as num?)?.toDouble();
          if (rx != null && ry != null) {
            onWebContextMenu!(rx, ry);
          }
        }
      }
    } catch (e) {
      // 다른 유형 메시지 무시
    }
  }

  /// 페이지 이동 (ArrowRight / ArrowLeft + 버스트 캡처)
  Future<void> navigatePage({required bool isNext}) async {
    if (kIsWeb) {
      stepWebVirtualPage(isNext ? 1 : -1);
      return;
    }

    final key = isNext ? 'ArrowRight' : 'ArrowLeft';
    final keyCode = isNext ? 39 : 37;

    final script = '''
      (function() {
        function triggerInDoc(doc, win) {
          if (!doc) return;
          var el = doc.activeElement || doc.body;
          ['keydown','keyup'].forEach(function(type) {
            el.dispatchEvent(new KeyboardEvent(type, {
              bubbles: true, cancelable: true,
              key: '$key', code: '${isNext ? 'ArrowRight' : 'ArrowLeft'}',
              keyCode: $keyCode, which: $keyCode
            }));
          });
          // 전자교과서 및 웹 뷰어 표준 다음/이전 버튼 DOM 자동 클릭 연동
          var selector = '${isNext ? '.btn_next, .btn-next, .next, .page-next, [title*="다음"], [aria-label*="다음"], [class*="next"], [id*="next"]' : '.btn_prev, .btn-prev, .prev, .page-prev, [title*="이전"], [aria-label*="이전"], [class*="prev"], [id*="prev"]'}';
          var btn = doc.querySelector(selector);
          if (btn && typeof btn.click === 'function') {
            try { btn.click(); } catch(e) {}
          }
        }
        triggerInDoc(document, window);
        var frames = document.querySelectorAll('iframe');
        for (var i = 0; i < frames.length; i++) {
          try {
            if (frames[i].contentDocument && frames[i].contentWindow) {
              triggerInDoc(frames[i].contentDocument, frames[i].contentWindow);
            }
          } catch(e) {}
        }
      })();
    ''';

    await _executeScript(script);
    _triggerBurstCapture();
  }

  // ─── 내부 구현 ─────────────────────────────────────────────

  void _startBackgroundPolling() {
    // 1.2초 실시간 페이지 감시 폴링
    _focusPollingTimer?.cancel();
    _focusPollingTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!_disposed) _requestHashFromJs();
    });

    // 5초 보조 폴링
    _fallbackPollingTimer?.cancel();
    _fallbackPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_disposed) _requestHashFromJs();
    });
  }

  /// 지수 버스트 캡처
  void _triggerBurstCapture() {
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
    if (kIsWeb) {
      try {
        final webHash = await captureCurrentBrowserScreenHash();
        if (webHash != null && webHash.isNotEmpty) {
          _onNewHash(webHash);
          return;
        }
      } catch (_) {}
    }
    await _executeScript(_hashJsScript);
  }

  void _onNewHash(String rawHash) {
    final newHash = TbpStorageService.toBinary256(rawHash) ?? rawHash;

    // 1. 현재 해시와 비교: 32비트 이하 차이면 동일 페이지(미세 노이즈)이므로 유지
    if (_currentDhash.isNotEmpty && _currentDhash != 'default') {
      final distToCurrent = TbpStorageService.hammingDistance(_currentDhash, newHash);
      if (distToCurrent <= _samePageThreshold) {
        return;
      }
    }

    // 2. 기존에 저장된/방문한 페이지 해시(_knownHashes) 중 가장 가까운 해시 검색 (<= 36비트)
    String canonicalHash = newHash;
    int bestDist = _knownMatchThreshold + 1;
    for (final known in _knownHashes) {
      final d = TbpStorageService.hammingDistance(newHash, known);
      if (d < bestDist) {
        bestDist = d;
        canonicalHash = known;
      }
    }
    _knownHashes.add(canonicalHash);

    if (_currentDhash != canonicalHash) {
      _currentDhash = canonicalHash;
      onDhashChanged(canonicalHash);
    }
  }

  Future<void> _executeScript(String script) async {
    try {
      if (!kIsWeb && Platform.isWindows && _winController != null) {
        await _winController!.executeScript(script);
      } else if (!kIsWeb && !Platform.isWindows && _androidController != null) {
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
}
