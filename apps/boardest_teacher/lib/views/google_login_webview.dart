import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/cloud_drive_service.dart';

class GoogleLoginWebview extends StatefulWidget {
  const GoogleLoginWebview({super.key});

  @override
  State<GoogleLoginWebview> createState() => _GoogleLoginWebviewState();
}

class _GoogleLoginWebviewState extends State<GoogleLoginWebview> {
  bool _isLoggingIn = false;

  @override
  void initState() {
    super.initState();
    _startChromeOAuth();
  }

  Future<void> _startChromeOAuth() async {
    setState(() => _isLoggingIn = true);
    final success = await CloudDriveService.instance.loginWithBrowserOAuth();
    if (mounted) {
      setState(() => _isLoggingIn = false);
      if (success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('🟢 Boardest 구글 연동 완료!')));
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Google 계정 연동',
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF16161A),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0F0E17),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF7F5AF0),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.open_in_browser_rounded,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Chrome 브라우저에서 구글 로그인 진행 중',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '열린 Chrome 창에서 Google 로그인 승인을 완료하시면\nBoardest 앱으로 인증 토큰이 자동 연동됩니다.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              if (_isLoggingIn)
                const CircularProgressIndicator(color: Color(0xFF7F5AF0))
              else
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Chrome 다시 열기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7F5AF0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                  onPressed: _startChromeOAuth,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
