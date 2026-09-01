import 'package:flutter/widgets.dart';

/// 플러그인이 호스트 UI와 상호작용하는 API
abstract class BstUiApi {
  /// 토스트 알림 메시지 표시
  void showToast(String message, {bool isError = false, Duration duration = const Duration(seconds: 2)});

  /// 호스트 메인 윈도우 최소화 / 복원 요청 (Windows)
  Future<void> minimizeWindow();
  Future<void> restoreWindow();

  /// 플러그인 전용 다이얼로그 / 모달 띄우기 요청
  Future<T?> showCustomDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  });

  /// 오버레이 모드 활성화 / 비활성화 토글 (예: 칠판 투명 필기 모드)
  Future<void> setOverlayVisible(bool visible);

  /// 전체 화면 모드 진입 / 해제 요청
  Future<void> setFullScreen(bool fullScreen);
}
