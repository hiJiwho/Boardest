import 'notification_helper_stub.dart'
    if (dart.library.html) 'notification_helper_web.dart' as impl;

/// 브라우저 알림 권한 획득 (웹 환경)
Future<void> requestWebNotificationPermission() => impl.requestWebNotificationPermission();

/// 웹 브라우저 데스크톱 알림 팝업 노출
void showWebBrowserNotification({required String title, required String body}) =>
    impl.showWebBrowserNotification(title: title, body: body);

/// 알림 효과음 재생 (웹 오디오 API 기반 맑은 알림음)
void playNotificationChime() => impl.playNotificationChime();
