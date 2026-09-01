import 'dart:async';
import '../models/cast_message.dart';

/// 교실 단위 1:1 전송 및 수신(bst-cast)을 관리하는 서비스
class CastService {
  final Map<String, StreamController<CastMessage>> _roomControllers = {};

  String getRoomId(String schoolId, int grade, int classNumber) {
    return '${schoolId}_${grade}-$classNumber';
  }

  /// 특정 교실(`schoolId_grade-class`)로 메시지를 전송합니다.
  Future<void> sendToClassroom({
    required String schoolId,
    required int grade,
    required int classNumber,
    required Map<String, dynamic> data,
    String? messageId,
    String? senderId,
    String? senderName,
    String? contentType,
  }) async {
    final roomId = getRoomId(schoolId, grade, classNumber);
    final message = CastMessage(
      id: messageId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
      senderId: senderId ?? 'unknown_sender',
      senderName: senderName ?? 'Teacher',
      schoolId: schoolId,
      grade: grade,
      classNumber: classNumber,
      contentType: contentType ?? 'custom',
      payload: data,
      timestamp: DateTime.now(),
    );

    if (_roomControllers.containsKey(roomId)) {
      _roomControllers[roomId]?.add(message);
    }
  }

  /// 특정 교실(`schoolId_grade-class`)의 데이터를 수신하는 스트림을 반환합니다.
  Stream<CastMessage> listenToClassroom({
    required String schoolId,
    required int grade,
    required int classNumber,
  }) {
    final roomId = getRoomId(schoolId, grade, classNumber);
    final controller = _roomControllers.putIfAbsent(
      roomId,
      () => StreamController<CastMessage>.broadcast(),
    );
    return controller.stream;
  }

  void dispose() {
    for (final controller in _roomControllers.values) {
      controller.close();
    }
    _roomControllers.clear();
  }
}
