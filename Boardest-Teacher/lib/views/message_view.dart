import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import '../services/storage_service.dart';
import '../services/cloud_drive_service.dart';

/// Boardest 라이브 웹 연동 학급 쪽지 및 공지 전송 뷰어 (https://boardest.web.app/note)
class MessageView extends StatefulWidget {
  final double scaleFactor;
  final VoidCallback? onBack;

  const MessageView({super.key, required this.scaleFactor, this.onBack});

  @override
  State<MessageView> createState() => _MessageViewState();
}

class _MessageViewState extends State<MessageView> {
  static const String _noteWebUrl = 'https://boardest.web.app/note';

  WebviewController? _winWebviewController;
  WebViewController? _androidWebController;
  bool _isWebviewInitialized = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows && !kIsWeb) {
      _initWindowsWebview();
    } else if (Platform.isAndroid) {
      _initAndroidWebview();
    }
  }

  Future<String> _buildWebUrlWithParams() async {
    try {
      final settings = await StorageService().getSettings();
      final cloud = CloudDriveService.instance;
      final schoolName = settings.selectedSchool?.name ?? cloud.schoolName ?? '학교';
      final regionName = settings.selectedSchool?.region ?? '서울';
      final teacherName = cloud.userName ?? '선생님';
      final email = cloud.userEmail ?? '';
      final token = cloud.accessToken ?? '';
      const hexColor = '00F5D4';

      return '$_noteWebUrl?IsApps=$hexColor&place=${Uri.encodeComponent(regionName)}&school=${Uri.encodeComponent(schoolName)}&name=${Uri.encodeComponent(teacherName)}&email=${Uri.encodeComponent(email)}&otp=${Uri.encodeComponent(token)}';
    } catch (_) {
      return '$_noteWebUrl?IsApps=00F5D4';
    }
  }

  Future<void> _initWindowsWebview() async {
    try {
      _winWebviewController = WebviewController();
      await _winWebviewController!.initialize();
      final targetUrl = await _buildWebUrlWithParams();
      await _winWebviewController!.loadUrl(targetUrl);
      if (mounted) setState(() => _isWebviewInitialized = true);
    } catch (e) {
      debugPrint('[MessageView] Windows WebView init error: $e');
    }
  }

  Future<void> _initAndroidWebview() async {
    final targetUrl = await _buildWebUrlWithParams();
    _androidWebController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(targetUrl));
    if (mounted) setState(() => _isWebviewInitialized = true);
  }

  void _reloadWebview() {
    if (Platform.isWindows && _winWebviewController != null) {
      _winWebviewController!.reload();
    } else if (Platform.isAndroid && _androidWebController != null) {
      _androidWebController!.reload();
    }
  }

  @override
  void dispose() {
    _winWebviewController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161A),
        elevation: 0,
        title: Text(
          '✉️ Boardest WEB 학급 쪽지 및 공지 발송',
          style: GoogleFonts.notoSansKr(color: const Color(0xFFFF8906), fontWeight: FontWeight.bold, fontSize: 18 * s),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFFF8906)),
            onPressed: _reloadWebview,
            tooltip: '웹페이지 새로고침',
          ),
        ],
      ),
      body: _buildWebViewLayer(),
    );
  }

  Widget _buildWebViewLayer() {
    if (Platform.isWindows && _isWebviewInitialized && _winWebviewController != null) {
      return Webview(_winWebviewController!);
    } else if (Platform.isAndroid && _androidWebController != null) {
      return WebViewWidget(controller: _androidWebController!);
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFFFF8906)),
            const SizedBox(height: 16),
            Text(
              '🌐 Boardest WEB 메시지 포털 로딩 중…',
              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }
  }
}
