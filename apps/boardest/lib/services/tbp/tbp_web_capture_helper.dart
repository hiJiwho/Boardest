import 'tbp_web_capture_stub.dart'
    if (dart.library.html) 'tbp_web_capture_web.dart' as impl;

/// Web 브라우저 화면 캡처 (Screen Capture API)
Future<String?> captureCurrentBrowserScreenHash() => impl.captureCurrentBrowserScreenHash();
