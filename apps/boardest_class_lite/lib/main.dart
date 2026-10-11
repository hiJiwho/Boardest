import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boardest Class Lite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BDA5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ClassLitePage(),
    );
  }
}

class ClassLitePage extends StatefulWidget {
  const ClassLitePage({super.key});

  @override
  State<ClassLitePage> createState() => _ClassLitePageState();
}

class _ClassLitePageState extends State<ClassLitePage> {
  static final Uri _siteUri = Uri.parse('https://boardest-class-lite.web.app');
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    unawaited(_initializeWebView());
  }

  Future<void> _initializeWebView() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setBackgroundColor(const Color(0xFF0F0E17));
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() {
            _isLoading = true;
            _loadError = null;
          });
        },
        onPageFinished: (_) {
          if (!mounted) return;
          setState(() => _isLoading = false);
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == false || !mounted) return;
          setState(() {
            _isLoading = false;
            _loadError = error.description;
          });
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null ||
              (uri.scheme != 'https' && request.url != 'about:blank')) {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ),
    );

    final androidController = _controller.platform as AndroidWebViewController;
    await androidController.setOnShowFileSelector(_selectFiles);
    await _controller.loadRequest(_siteUri);
  }

  Future<List<String>> _selectFiles(FileSelectorParams params) async {
    if (params.mode == FileSelectorMode.save) return const [];
    final selectedFiles = await FilePicker.pickFiles(
      dialogTitle: 'Class Lite 파일 선택',
    );
    return selectedFiles
        .take(
          params.mode == FileSelectorMode.openMultiple
              ? selectedFiles.length
              : 1,
        )
        .map((file) => file.path)
        .whereType<String>()
        .toList();
  }

  Future<void> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: Scaffold(
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_isLoading)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0xFF0F0E17),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image(
                            image: AssetImage('assets/icons/app_logo.png'),
                            width: 84,
                            height: 84,
                          ),
                          SizedBox(height: 16),
                          Text('Boardest Class Lite  v4.0.2'),
                          SizedBox(height: 20),
                          CircularProgressIndicator(),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_loadError case final error?)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off, size: 40),
                        const SizedBox(height: 12),
                        const Text('Class Lite 사이트에 연결할 수 없습니다.'),
                        const SizedBox(height: 8),
                        Text(error, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _controller.loadRequest(_siteUri),
                          icon: const Icon(Icons.refresh),
                          label: const Text('다시 시도'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
