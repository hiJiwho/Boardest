import 'package:flutter_test/flutter_test.dart';
import 'package:bst_cast/bst_cast.dart';

void main() {
  group('CastMessage Serialization Tests', () {
    test('CastMessage serialization and deserialization', () {
      final now = DateTime.utc(2026, 8, 21, 10, 0, 0);
      final msg = CastMessage(
        id: 'msg_001',
        senderId: 'teacher_hong',
        senderName: '홍길동',
        schoolId: 'ydm',
        grade: 2,
        classNumber: 3,
        contentType: 'tbp',
        payload: {'tbpUrl': 'https://drive.google.com/test.tbp', 'page': 5},
        timestamp: now,
      );

      expect(msg.roomId, 'ydm_2-3');

      final json = msg.toJson();
      expect(json['id'], 'msg_001');
      expect(json['senderName'], '홍길동');
      expect(json['grade'], 2);
      expect(json['classNumber'], 3);
      expect(json['contentType'], 'tbp');
      expect(json['payload']['page'], 5);

      final restored = CastMessage.fromJson(json);
      expect(restored.id, 'msg_001');
      expect(restored.senderName, '홍길동');
      expect(restored.roomId, 'ydm_2-3');
      expect(restored.contentType, 'tbp');
      expect(restored.payload['tbpUrl'], contains('test.tbp'));
      expect(restored.timestamp, equals(now));
      expect(restored.toString(), contains('ydm_2-3'));
    });

    test('CastSignalingData serialization and deserialization', () {
      final now = DateTime.utc(2026, 8, 21, 10, 0, 0);
      final signaling = CastSignalingData(
        type: 'offer',
        senderId: 'device_a',
        targetId: 'board_b',
        data: {'sdp': 'v=0\r\no=...'},
        timestamp: now,
      );

      final json = signaling.toJson();
      expect(json['type'], 'offer');
      expect(json['senderId'], 'device_a');
      expect(json['targetId'], 'board_b');

      final restored = CastSignalingData.fromJson(json);
      expect(restored.type, 'offer');
      expect(restored.senderId, 'device_a');
      expect(restored.targetId, 'board_b');
      expect(restored.data['sdp'], contains('v=0'));
    });
  });

  group('CastService Room Messaging Tests', () {
    test('CastService dispatches and listens for classroom casts', () async {
      final service = CastService();
      final receivedMessages = <CastMessage>[];

      final stream = service.listenToClassroom(
        schoolId: 'ydm',
        grade: 1,
        classNumber: 4,
      );

      final sub = stream.listen(receivedMessages.add);

      await service.sendToClassroom(
        schoolId: 'ydm',
        grade: 1,
        classNumber: 4,
        messageId: 'cast_1',
        senderName: 'Teacher Park',
        contentType: 'notice',
        data: {'message': '수업이 시작되었습니다.'},
      );

      // Give event loop time to dispatch
      await Future.delayed(const Duration(milliseconds: 10));

      expect(receivedMessages.length, 1);
      expect(receivedMessages.first.id, 'cast_1');
      expect(receivedMessages.first.senderName, 'Teacher Park');
      expect(receivedMessages.first.payload['message'], '수업이 시작되었습니다.');

      await sub.cancel();
      service.dispose();
    });
  });
}
