import 'dart:async';

/// 전자칠판 ↔ 교사용 PC 실시간 Cast 및 원격 제어 연동 API
abstract class BstCastApi {
  /// Cast 세션 연결 여부
  bool get isConnected;

  /// 상대 기기로 실시간 메시지/명령 전송 (예: 판서 스트로크, 교안 전환)
  Future<void> sendData(String action, Map<String, dynamic> payload);

  /// 상대 기기로부터 수신된 데이터 스트림
  Stream<Map<String, dynamic>> get onDataReceived;

  /// 상대 기기와의 연결 상태 변경 스트림
  Stream<bool> get onConnectionChanged;
}
