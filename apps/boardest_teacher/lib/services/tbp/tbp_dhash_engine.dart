import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// BoardBook 오리지널 초고속 무결점 페이지 감지 엔진
/// - DOM 페이지 식별자(.page-num, #pageNo 등) 및 URL, document.title, 고속 텍스트 해시로 실시간 페이지 감지
/// - 페이지가 전환되자마자 0.1~0.2초 이내에 즉시 감지하여 지연 없이 판서 교체
/// - 네비게이션 시 450ms 쿨다운 가드로 2페이지 연속 넘어감 완벽 차단
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
  DateTime? _lastNavTime;

  Timer? _focusPollingTimer;
  bool _disposed = false;

  void registerKnownHashes(Iterable<String> hashes) {
    for (final h in hashes) {
      if (h.isNotEmpty && h != 'default') {
        _knownHashes.add(h);
      }
    }
  }

  /// BoardBook 오리지널 고속 JS 스크립트 + 1536px 고정 및 창 크기 맞춤 동적 배율(Auto-Fit Scale)
  static const String _hashJsScript = '''
    (function() {
      if (!window.__bstNativeGettersSaved) {
        window.__bstNativeGettersSaved = true;
        try {
          var dWinW = Object.getOwnPropertyDescriptor(window, 'innerWidth') || Object.getOwnPropertyDescriptor(Window.prototype, 'innerWidth');
          var dWinH = Object.getOwnPropertyDescriptor(window, 'innerHeight') || Object.getOwnPropertyDescriptor(Window.prototype, 'innerHeight');
          var dDocW = Object.getOwnPropertyDescriptor(Element.prototype, 'clientWidth') || Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'clientWidth');
          var dDocH = Object.getOwnPropertyDescriptor(Element.prototype, 'clientHeight') || Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'clientHeight');
          window.__bstGetRealW = function() {
            try {
              if (dWinW && dWinW.get) return dWinW.get.call(window);
              if (dDocW && dDocW.get) return dDocW.get.call(document.documentElement);
            } catch (e) {}
            return window.outerWidth || screen.width || 1536;
          };
          window.__bstGetRealH = function() {
            try {
              if (dWinH && dWinH.get) return dWinH.get.call(window);
              if (dDocH && dDocH.get) return dDocH.get.call(document.documentElement);
            } catch (e) {}
            return window.outerHeight || screen.height || 864;
          };
          Object.defineProperty(window, 'innerWidth', { get: function() { return 1536; }, configurable: true });
          Object.defineProperty(window, 'innerHeight', { get: function() { return 864; }, configurable: true });
          Object.defineProperty(document.documentElement, 'clientWidth', { get: function() { return 1536; }, configurable: true });
          Object.defineProperty(document.documentElement, 'clientHeight', { get: function() { return 864; }, configurable: true });
        } catch (ge) {}
      }

      function sync1536Scale() {
        if (window.__bstInSyncScale) return;
        window.__bstInSyncScale = true;
        try {
          var targetW = 1536;
          var targetH = 864;
          var winW = (window.__bstGetRealW ? window.__bstGetRealW() : window.innerWidth) || screen.width || 1536;
          var winH = (window.__bstGetRealH ? window.__bstGetRealH() : window.innerHeight) || screen.height || 864;
          if (!winW || !winH || winW <= 0 || winH <= 0) {
            window.__bstInSyncScale = false;
            return;
          }

          var scale = Math.min(winW / targetW, winH / targetH);
          if (scale <= 0) scale = 1.0;

          var offsetX = Math.max(0, (winW - (targetW * scale)) / 2);
          var offsetY = Math.max(0, (winH - (targetH * scale)) / 2);

          var meta = document.querySelector('meta[name="viewport"]');
          if (!meta && document.head) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            document.head.appendChild(meta);
          }
          if (meta) {
            meta.content = 'width=1536, initial-scale=' + scale.toFixed(4) + ', maximum-scale=' + scale.toFixed(4) + ', user-scalable=no';
          }

          var styleId = 'bst-1536-lock-style';
          var styleEl = document.getElementById(styleId);
          if (!styleEl && document.head) {
            styleEl = document.createElement('style');
            styleEl.id = styleId;
            document.head.appendChild(styleEl);
          }
          if (styleEl) {
            styleEl.textContent = 'html { width: 100% !important; height: 100% !important; margin: 0 !important; padding: 0 !important; overflow: hidden !important; background-color: #0F0E17 !important; } ' +
              'body { width: 1536px !important; min-width: 1536px !important; max-width: 1536px !important; height: 864px !important; min-height: 864px !important; max-height: 864px !important; margin: 0 !important; padding: 0 !important; overflow: hidden !important; box-sizing: border-box !important; transform-origin: 0 0 !important; transform: translate(' + offsetX.toFixed(2) + 'px, ' + offsetY.toFixed(2) + 'px) scale(' + scale.toFixed(4) + ') !important; -webkit-text-size-adjust: 100% !important; text-size-adjust: 100% !important; }';
          }

          if (!window.__bstInitialResizeDispatched) {
            window.__bstInitialResizeDispatched = true;
            setTimeout(function() {
              try { window.dispatchEvent(new Event('resize')); } catch (re) {}
            }, 60);
          }
        } catch (ve) {}
        window.__bstInSyncScale = false;
      }

      sync1536Scale();
      if (!window.__bstScaleBound) {
        window.__bstScaleBound = true;
        window.addEventListener('resize', sync1536Scale);
      }

      function postToFlutter(payload) {
        var msg = JSON.stringify(payload);
        if (window.chrome && window.chrome.webview) {
          window.chrome.webview.postMessage(msg);
        }
        if (window.TbpChannel && window.TbpChannel.postMessage) {
          window.TbpChannel.postMessage(msg);
        }
      }

      function bindDocEvents(doc, win, offsetLeft, offsetTop) {
        if (!doc || doc.__bstBound) return;
        doc.__bstBound = true;

        doc.addEventListener('contextmenu', function(e) {
          e.preventDefault();
          e.stopPropagation();
          var vw = (window.__bstGetRealW ? window.__bstGetRealW() : window.innerWidth) || 1536;
          var vh = (window.__bstGetRealH ? window.__bstGetRealH() : window.innerHeight) || 864;
          var cx = (e.clientX || 0) + (offsetLeft || 0);
          var cy = (e.clientY || 0) + (offsetTop || 0);
          postToFlutter({
            type: 'hotspotContext',
            rx: Math.max(0.02, Math.min(0.98, cx / vw)),
            ry: Math.max(0.02, Math.min(0.98, cy / vh))
          });
          return false;
        }, true);
      }

      function getFastHash(str) {
        var hash = 0;
        for (var i = 0; i < str.length; i++) {
          hash = ((hash << 5) - hash) + str.charCodeAt(i);
          hash |= 0;
        }
        return 'dhash_' + Math.abs(hash);
      }

      function getDocPageId(doc, win) {
        if (!doc) return '';
        try {
          var w = win || window;
          if (w.Ui && w.Ui.now) {
            var scene = w.Ui.scene || 'home';
            if (scene === 'home') return 'ui_home';
            var pno = w.Ui.now.ebook_pno || '';
            var mcode = w.Ui.now.mcode || '';
            var pseq = w.Ui.now.std_pseq || '';
            if (pno || mcode || pseq) {
              return 'ui_' + scene + '_' + pno + '_' + mcode + '_' + pseq;
            }
          }

          var loc = (w && w.location) ? w.location : window.location;
          if (loc && loc.hostname && loc.hostname.indexOf('canva.com') !== -1) {
            var chash = (loc.hash && loc.hash.length > 1)
                ? loc.hash.replace(/[^a-zA-Z0-9_-]/g, '_')
                : '_1';
            return 'hash_' + chash;
          }

          var selectors = [
            '.page-num', '.pageNum', '#pageNo', '#page_num', '.page_num',
            '.page-current', '#currentPage', '.current-page', '.textbook-page',
            '#spnPage', '.spn_page', '.page_input', 'input.page', '.cur_page', '#curPage',
            '#txtPage', '.txt_page', '#nowPage', '.now_page'
          ];
          for (var s = 0; s < selectors.length; s++) {
            var el = doc.querySelector(selectors[s]);
            if (el && (el.offsetParent !== null || (el.getClientRects && el.getClientRects().length > 0))) {
              var val = (el.value || el.innerText || el.textContent || '').trim();
              if (val && val.length > 0 && val.length <= 25) {
                return 'page_' + val.replace(/[^a-zA-Z0-9_-]/g, '_');
              }
            }
          }

          if (loc && loc.hash && loc.hash.length > 1) {
            return 'hash_' + loc.hash.replace(/[^a-zA-Z0-9_-]/g, '_');
          }
        } catch(e) {}
        return '';
      }

      window.checkPage = function() {
        var detectedId = getDocPageId(document, window);

        var frames = document.querySelectorAll('iframe');
        if (!detectedId) {
          for (var f = 0; f < frames.length; f++) {
            try {
              if (frames[f].contentDocument) {
                bindDocEvents(frames[f].contentDocument, frames[f].contentWindow, 0, 0);
                detectedId = getDocPageId(frames[f].contentDocument, frames[f].contentWindow);
                if (detectedId) break;
              }
            } catch(fe) {}
          }
        }

        if (!detectedId) {
          var targetDoc = document;
          for (var f2 = 0; f2 < frames.length; f2++) {
            try {
              if (frames[f2].contentDocument && frames[f2].contentDocument.body) {
                targetDoc = frames[f2].contentDocument;
                break;
              }
            } catch(fe2) {}
          }
          var bodyText = (targetDoc.body ? (targetDoc.body.innerText || '') : '').replace(/\\s+/g, '').substring(0, 400);
          var imgSrcs = '';
          try {
            var imgs = targetDoc.querySelectorAll('img, canvas, iframe');
            for (var im = 0; im < Math.min(imgs.length, 12); im++) {
              if (imgs[im].offsetParent !== null) {
                imgSrcs += (imgs[im].src || imgs[im].id || imgs[im].className || '');
              }
            }
          } catch(ie) {}
          var raw = window.location.pathname + '_' + window.location.search + '_' + bodyText + '_' + imgSrcs;
          detectedId = getFastHash(raw);
        }

        if (detectedId && detectedId !== window.__bstLastPageId) {
          window.__bstLastPageId = detectedId;
          postToFlutter({
            type: 'dhashResult',
            hash: detectedId
          });
        }
      };

      bindDocEvents(document, window, 0, 0);
      window.checkPage();

      if (!window.__boardestDhashInjected) {
        window.__boardestDhashInjected = true;
        setInterval(window.checkPage, 250);
        window.addEventListener('hashchange', window.checkPage);
        window.addEventListener('popstate', window.checkPage);
        window.addEventListener('click', function() { setTimeout(window.checkPage, 120); });
        window.addEventListener('keyup', function() { setTimeout(window.checkPage, 120); });
      }
    })();
  ''';

  void startTracker([dynamic winWebview, dynamic androidWebview]) {
    if (winWebview != null && winWebview is WebviewController) {
      attachWindowsWebview(winWebview);
    } else if (androidWebview != null && androidWebview is WebViewController) {
      attachAndroidWebview(androidWebview);
    } else {
      _startBackgroundPolling();
      _requestHashFromJs();
    }
  }

  void attachWindowsWebview(WebviewController controller) {
    _winController = controller;
    _startBackgroundPolling();
    _requestHashFromJs();
  }

  void attachAndroidWebview(WebViewController controller) {
    _androidController = controller;
    _startBackgroundPolling();
    _requestHashFromJs();
  }

  void stepWebVirtualPage(int delta, {bool? isNext}) {
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

  void triggerBurstCapture() => _requestHashFromJs();

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
    } catch (_) {}
  }

  /// 페이지 이동 (450ms 쿨다운 가드로 2페이지 연속 넘어감 완벽 차단)
  Future<void> navigatePage({required bool isNext}) async {
    final now = DateTime.now();
    if (_lastNavTime != null && now.difference(_lastNavTime!).inMilliseconds < 450) {
      return; // 450ms 디바운스로 2페이지 연속 점프 방지
    }
    _lastNavTime = now;

    if (kIsWeb) {
      stepWebVirtualPage(isNext ? 1 : -1);
      return;
    }

    final key = isNext ? 'ArrowRight' : 'ArrowLeft';
    final keyCode = isNext ? 39 : 37;

    final script = '''
      (function() {
        var clicked = false;
        function tryClickBtn(doc) {
          if (!doc || clicked) return false;
          var sel = '${isNext ? '.btn_next, .btn-next, .next, .page-next, [title*="다음"], [aria-label*="다음"], [aria-label*="Next"], [class*="next"], [id*="next"]' : '.btn_prev, .btn-prev, .prev, .page-prev, [title*="이전"], [aria-label*="이전"], [aria-label*="Previous"], [class*="prev"], [id*="prev"]'}';
          var list = doc.querySelectorAll(sel);
          for (var i = 0; i < list.length; i++) {
            var b = list[i];
            if (b && typeof b.click === 'function' && (b.offsetParent !== null || (b.getClientRects && b.getClientRects().length > 0))) {
              try { b.click(); clicked = true; return true; } catch(e) {}
            }
          }
          return false;
        }

        if (window.Ui && window.Ui.scene === 'home' && ${isNext ? 'true' : 'false'}) {
          var firstCh = document.querySelector('#home .list li a, #home .list li, .main_list li a, .toc li a');
          if (firstCh && typeof firstCh.click === 'function') {
            try { firstCh.click(); clicked = true; } catch(e) {}
          }
        }

        var frames = document.querySelectorAll('iframe');
        if (!clicked) {
          for (var i = 0; i < frames.length; i++) {
            try {
              if (frames[i].contentDocument && tryClickBtn(frames[i].contentDocument)) break;
            } catch(e) {}
          }
        }
        if (!clicked) {
          tryClickBtn(document);
        }

        // 버튼이 없는 경우에만 keydown 단 1회만 디스패치
        if (!clicked) {
          var targetDoc = document;
          for (var i = 0; i < frames.length; i++) {
            try {
              if (frames[i].contentDocument) { targetDoc = frames[i].contentDocument; break; }
            } catch(e) {}
          }
          var el = targetDoc.activeElement || targetDoc.body;
          el.dispatchEvent(new KeyboardEvent('keydown', {
            bubbles: true, cancelable: true,
            key: '$key', code: '$key',
            keyCode: $keyCode, which: $keyCode
          }));
        }

        if (window.checkPage) {
          setTimeout(window.checkPage, 120);
        }
      })();
    ''';

    await _executeScript(script);
  }

  void _startBackgroundPolling() {
    _focusPollingTimer?.cancel();
    _focusPollingTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!_disposed) _requestHashFromJs();
    });
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
    if (newHash.isEmpty) return;
    _knownHashes.add(newHash);

    if (_currentDhash != newHash) {
      _currentDhash = newHash;
      onDhashChanged(newHash);
    }
  }

  Future<void> _executeScript(String script) async {
    try {
      if (!kIsWeb && Platform.isWindows && _winController != null) {
        await _winController!.executeScript(script);
      } else if (!kIsWeb && !Platform.isWindows && _androidController != null) {
        await _androidController!.runJavaScript(script);
      }
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _focusPollingTimer?.cancel();
  }
}
