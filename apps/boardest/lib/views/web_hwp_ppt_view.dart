import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import '../helpers/iframe_view_helper.dart';

/// Android / Web / Windows Cross-Platform 전용 HWP & PPTX 뷰어 (구글 슬라이드/뷰어 & 페이지 넘김 지원)
class WebHwpPptView extends StatefulWidget {
  final String filePathOrUrl;
  final String title;
  final double scaleFactor;
  final bool isPpt;

  const WebHwpPptView({
    super.key,
    required this.filePathOrUrl,
    required this.title,
    this.scaleFactor = 1.0,
    this.isPpt = false,
  });

  @override
  State<WebHwpPptView> createState() => _WebHwpPptViewState();
}

class _WebHwpPptViewState extends State<WebHwpPptView> {
  WebViewController? _mobileController;
  WebviewController? _winWebviewController;
  bool _isWebviewInitialized = false;
  String _webViewType = '';
  String _targetUrl = '';

  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _initWebview();
  }

  Future<void> _initWebview() async {
    String targetUrl = widget.filePathOrUrl;
    if (widget.filePathOrUrl.startsWith('http')) {
      if (widget.filePathOrUrl.contains('drive.google.com') || widget.filePathOrUrl.contains('docs.google.com')) {
        targetUrl = widget.filePathOrUrl;
      } else {
        targetUrl = 'https://docs.google.com/viewer?embedded=true&url=${Uri.encodeComponent(widget.filePathOrUrl)}';
      }
    } else {
      targetUrl = 'https://docs.google.com/viewer?embedded=true&url=${Uri.encodeComponent('https://boardest.web.app/viewer?file=${widget.title}')}';
    }

    _targetUrl = targetUrl;

    if (kIsWeb) {
      _webViewType = 'bst-ppt-iframe-${widget.filePathOrUrl.hashCode}-${DateTime.now().millisecondsSinceEpoch}';
      if (mounted) setState(() => _isWebviewInitialized = true);
    } else if (Platform.isWindows) {
      try {
        _winWebviewController = WebviewController();
        await _winWebviewController!.initialize();
        await _winWebviewController!.loadUrl(targetUrl);
        if (mounted) setState(() => _isWebviewInitialized = true);
      } catch (e) {
        debugPrint('[WebHwpPptView] Windows Webview error: $e');
      }
    } else {
      _mobileController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(targetUrl));
      if (mounted) setState(() => _isWebviewInitialized = true);
    }
  }

  void _nextPage() {
    setState(() => _currentPage++);
    if (kIsWeb) return;
    const js =
        "window.scrollBy({top: window.innerHeight * 0.9, behavior: 'smooth'});";
    if (!kIsWeb && Platform.isWindows && _winWebviewController != null) {
      _winWebviewController!.executeScript(js);
    } else if (_mobileController != null) {
      _mobileController!.runJavaScript(js);
    }
  }

  void _prevPage() {
    if (_currentPage > 1) {
      setState(() => _currentPage--);
      if (kIsWeb) return;
      const js =
          "window.scrollBy({top: -window.innerHeight * 0.9, behavior: 'smooth'});";
      if (!kIsWeb && Platform.isWindows && _winWebviewController != null) {
        _winWebviewController!.executeScript(js);
      } else if (_mobileController != null) {
        _mobileController!.runJavaScript(js);
      }
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && Platform.isWindows) {
      _winWebviewController?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    return Scaffold(
      backgroundColor: const Color(0xFF131418),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar & Page Controls
            Container(
              height: 54 * s,
              padding: EdgeInsets.symmetric(horizontal: 16 * s),
              color: const Color(0xFF1C1D24),
              child: Row(
                children: [
                  Icon(
                    widget.isPpt
                        ? Icons.slideshow_rounded
                        : Icons.description_rounded,
                    color: widget.isPpt
                        ? const Color(0xFFEF4565)
                        : const Color(0xFF2EC4B6),
                    size: 22 * s,
                  ),
                  SizedBox(width: 8 * s),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 14 * s,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Page Navigation Controls (한봄 스타일 슬라이드/페이지 넘김)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8 * s,
                      vertical: 2 * s,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10 * s),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.chevron_left_rounded,
                            color: Colors.white,
                            size: 22 * s,
                          ),
                          tooltip: '이전 페이지',
                          onPressed: _prevPage,
                        ),
                        Text(
                          '$_currentPage 페이지',
                          style: GoogleFonts.notoSansKr(
                            color: Colors.white,
                            fontSize: 12 * s,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white,
                            size: 22 * s,
                          ),
                          tooltip: '다음 페이지',
                          onPressed: _nextPage,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12 * s),

                  // Close Button
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 22 * s,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Main Web Viewer Body
            Expanded(
              child: _isWebviewInitialized
                  ? (kIsWeb
                      ? getIframeViewWidget(_webViewType, _targetUrl)
                      : (Platform.isWindows && _winWebviewController != null
                          ? Webview(_winWebviewController!)
                          : (_mobileController != null
                              ? WebViewWidget(controller: _mobileController!)
                              : const SizedBox.shrink())))
                  : const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2EC4B6),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
