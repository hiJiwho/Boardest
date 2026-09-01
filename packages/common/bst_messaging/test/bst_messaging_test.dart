import 'package:flutter_test/flutter_test.dart';
import 'package:bst_messaging/bst_messaging.dart';

void main() {
  group('Message Model Serialization Tests', () {
    test('Message toJson and fromJson round-trip', () {
      final now = DateTime.utc(2026, 8, 21, 15, 30, 0);
      final message = Message(
        id: 'msg_100',
        senderId: 'teacher_1',
        receiverId: 'board_2',
        content: '수업 준비 완료되었습니다.',
        timestamp: now,
        isRead: false,
      );

      final json = message.toJson();
      expect(json['id'], 'msg_100');
      expect(json['senderId'], 'teacher_1');
      expect(json['receiverId'], 'board_2');
      expect(json['content'], '수업 준비 완료되었습니다.');
      expect(json['isRead'], isFalse);

      final restored = Message.fromJson(json);
      expect(restored.id, 'msg_100');
      expect(restored.senderId, 'teacher_1');
      expect(restored.receiverId, 'board_2');
      expect(restored.content, '수업 준비 완료되었습니다.');
      expect(restored.timestamp, equals(now));
      expect(restored.isRead, isFalse);
    });

    test('Message.fromJson handles null and missing fields gracefully', () {
      final restored = Message.fromJson({});
      expect(restored.id, '');
      expect(restored.senderId, '');
      expect(restored.receiverId, '');
      expect(restored.content, '');
      expect(restored.isRead, isFalse);
      expect(restored.timestamp, isNotNull);
    });
  });

  group('InMemoryMessagingService Tests', () {
    test('sendMessage, markMessageAsRead and getMessagesStream functionality', () async {
      final service = InMemoryMessagingService();
      final streamMessages = <List<Message>>[];

      final stream = service.getMessagesStream('teacher_1', 'board_2');
      final sub = stream.listen(streamMessages.add);

      final msg1 = Message(
        id: 'm1',
        senderId: 'teacher_1',
        receiverId: 'board_2',
        content: '안부 인사',
        timestamp: DateTime.now(),
      );

      final msg2 = Message(
        id: 'm2',
        senderId: 'board_2',
        receiverId: 'teacher_1',
        content: '확인했습니다.',
        timestamp: DateTime.now(),
      );

      final unrelatedMsg = Message(
        id: 'm3',
        senderId: 'other_user',
        receiverId: 'someone_else',
        content: '무관한 메시지',
        timestamp: DateTime.now(),
      );

      await service.sendMessage(msg1);
      await service.sendMessage(msg2);
      await service.sendMessage(unrelatedMsg);

      await Future.delayed(const Duration(milliseconds: 10));

      expect(service.allMessages.length, 3);
      expect(streamMessages.last.length, 2);
      expect(streamMessages.last.any((m) => m.id == 'm1'), isTrue);
      expect(streamMessages.last.any((m) => m.id == 'm2'), isTrue);
      expect(streamMessages.last.any((m) => m.id == 'm3'), isFalse);

      await service.markMessageAsRead('m1');
      await Future.delayed(const Duration(milliseconds: 10));

      final updatedM1 = service.allMessages.firstWhere((m) => m.id == 'm1');
      expect(updatedM1.isRead, isTrue);

      await sub.cancel();
      service.dispose();
    });
  });
}
