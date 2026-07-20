import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import '../services/bst_cloud_service.dart';
import '../services/youtube_embed_service.dart';

/// Boardest-Board 전용 100% 순수 클린 비디오 디스플레이 (교사 앱 송출 수신 뷰어)
class YoutubeBoardView extends StatefulWidget {
  final double scaleFactor;
  final String? initialUrl;
  final String? filePath; // .YT 파일 경로
  final VoidCallback? onBack;

  const YoutubeBoardView({
    super.key,
    required this.scaleFactor,
    this.initialUrl,
    this.filePath,
    this.onBack,
  });

  @override
  State<YoutubeBoardView> createState() => _YoutubeBoardViewState();
}

class _YoutubeBoardViewState extends State<YoutubeBoardView> {
  WebviewController? _winWebviewController;
  WebViewController? _androidWebController;

  bool _isWebviewInitialized = false;
  String _currentVideoUrl = 'https://www.youtube.com';
  String _playlistTitle = '수업 영상 시청';
  bool _useEmbedPlayer = true;

  void _toggleCleanViewMode() {
    setState(() {
      _useEmbedPlayer = !_useEmbedPlayer;
    });
    if (_useEmbedPlayer) {
      _loadUrl(YouTubeEmbedService.convertToEmbedUrl(_currentVideoUrl));
    } else {
      final videoId = YouTubeEmbedService.extractVideoId(_currentVideoUrl);
      final cleanWatchUrl = videoId != null ? 'https://www.youtube.com/watch?v=$videoId' : _currentVideoUrl;
      _loadUrl(cleanWatchUrl);
    }
  }

  static const String _cleanYoutubeCss = '''
    /* 검색창, 사이드바, 알고리즘, 헤더/푸터 및 광고 완전 제거 */
    #masthead-container, #related, #secondary, ytd-browse[page-subtype="home"],
    .ytp-ce-element, .ytd-compact-autoplay-toggle,
    .video-ads, .ytp-ad-module, .ytp-ad-overlay-container,
    ytd-banner-promo-renderer, ytd-statement-banner-renderer,
    #comments, ytd-watch-flexy[flexy] #secondary.ytd-watch-flexy {
      display: none !important;
    }
  ''';

  @override
  void initState() {
    super.initState();
    _currentVideoUrl = widget.initialUrl ?? _currentVideoUrl;

    // .YT JSON 파일 읽기
    if (widget.filePath != null && widget.filePath!.isNotEmpty) {
      try {
        final file = File(widget.filePath!);
        if (file.existsSync()) {
          final content = file.readAsStringSync();
          final data = jsonDecode(content);
          if (data['url'] != null) _currentVideoUrl = data['url'];
          if (data['title'] != null) _playlistTitle = data['title'];
        }
      } catch (e) {
        debugPrint('[YoutubeBoardView] Board .YT parse error: $e');
      }
    }

    // 교사 앱 동기화 리스너 등록
    BstCloudService.instance.listenSyncState('yt_playlist', (data) {
      if (mounted && data != null) {
        final newUrl = data['currentUrl'];
        if (newUrl != null && newUrl != _currentVideoUrl) {
          setState(() {
            _currentVideoUrl = newUrl;
            if (data['playlistTitle'] != null) {
              _playlistTitle = data['playlistTitle'];
            }
          });
          _loadUrl(_currentVideoUrl);
        }
      }
    });

    if (Platform.isWindows) {
      _initWindowsWebview();
    } else if (Platform.isAndroid) {
      _initAndroidWebview();
    }
  }

  Future<void> _initWindowsWebview() async {
    try {
      _winWebviewController = WebviewController();
      await _winWebviewController!.initialize();
      _winWebviewController!.url.listen((url) {
        if (mounted) _injectCleanCssWindows();
      });
      await _winWebviewController!.loadUrl(_currentVideoUrl);
      if (mounted) setState(() => _isWebviewInitialized = true);
    } catch (e) {
      debugPrint('[YoutubeBoardView] Init error: $e');
    }
  }

  void _loadUrl(String targetUrl) {
    final embedUrl = YouTubeEmbedService.convertToEmbedUrl(targetUrl);
    _currentVideoUrl = embedUrl;
    if (Platform.isWindows && _winWebviewController != null) {
      _winWebviewController!.loadUrl(embedUrl);
    } else if (Platform.isAndroid && _androidWebController != null) {
      _androidWebController!.loadRequest(Uri.parse(embedUrl));
    }
  }

  void _injectCleanCssWindows() {
    if (_winWebviewController == null) return;
    final js = '''
      (function() {
        var style = document.getElementById('bst-yt-clean-style');
        if (!style) {
          style = document.createElement('style');
          style.id = 'bst-yt-clean-style';
          style.innerHTML = `$_cleanYoutubeCss`;
          document.head.appendChild(style);
        }
      })();
    ''';
    _winWebviewController!.executeScript(js);
  }

  void _initAndroidWebview() {
    _androidWebController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (mounted) {
              _androidWebController?.runJavaScript('''
                var style = document.createElement('style');
                style.innerHTML = `$_cleanYoutubeCss`;
                document.head.appendChild(style);
              ''');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_currentVideoUrl));
    setState(() => _isWebviewInitialized = true);
  }

  @override
  void dispose() {
    _winWebviewController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Stack(
          children: [
            // Pure Fullscreen Video Viewport (100% Clean)
            Positioned.fill(
              child: _buildWebView(),
            ),

            // Top Minimal Floating Badge Bar
            Positioned(
              top: 12 * scale,
              left: 16 * scale,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 6 * scale),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20 * scale),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tv_rounded, color: Colors.redAccent, size: 18),
                    SizedBox(width: 8 * scale),
                    Text(
                      _playlistTitle,
                      style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13 * scale),
                    ),
                  ],
                ),
              ),
            ),

            // Top Right Back Button
            Positioned(
              top: 12 * scale,
              right: 16 * scale,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else {
                    Navigator.pop(context);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    if (Platform.isWindows && _isWebviewInitialized && _winWebviewController != null) {
      return Webview(_winWebviewController!);
    } else if (Platform.isAndroid && _androidWebController != null) {
      return WebViewWidget(controller: _androidWebController!);
    } else {
      return Center(
        child: Text(
          '▶️ 클린 영상 수신 준비 중…',
          style: GoogleFonts.notoSansKr(color: Colors.white38),
        ),
      );
    }
  }
}
