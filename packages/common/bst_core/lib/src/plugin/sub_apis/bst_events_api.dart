import 'dart:async';

/// Boardest 전역 이벤트 버스 연동 API
abstract class BstEventsApi {
  /// 특정 토픽의 이벤트 구독 (예: 'timetable.periodChanged', 'lesson.start', 'custom.event')
  Stream<dynamic> on(String eventType);

  /// 특정 토픽으로 이벤트 브로드캐스트
  void emit(String eventType, [dynamic data]);

  /// 표준 보디스트 시스템 이벤트 스트림
  Stream<int> get onPeriodChanged; // 교시 변경
  Stream<String> get onSubjectSelected; // 과목 선택
  Stream<bool> get onScreenLockChanged; // 화면 잠금/절전 상태 변경
}
