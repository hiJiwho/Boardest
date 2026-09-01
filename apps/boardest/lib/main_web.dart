import 'package:flutter/material.dart';

void main() {
  runApp(const BoardestWebFallbackApp());
}

class BoardestWebFallbackApp extends StatelessWidget {
  const BoardestWebFallbackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boardest (Web)',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0E17),
      ),
      home: const WebFallbackScreen(),
    );
  }
}

class WebFallbackScreen extends StatelessWidget {
  const WebFallbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.desktop_windows, size: 80, color: Color(0xFF7F5AF0)),
            const SizedBox(height: 24),
            const Text(
              'Boardest Pro 전자칠판',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text(
              '전자칠판 메인 프로그램은 윈도우 데스크톱 전용 소프트웨어입니다.\nHWP/PPT 오버레이, 로컬 파일 시스템, USB 자동 인식 등\n강력한 네이티브 기능을 위해 윈도우 PC에서 앱을 다운로드하여 실행해주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Windows 다운로드 (v3.4)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7F5AF0),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                // 다운로드 로직
              },
            ),
          ],
        ),
      ),
    );
  }
}
