import 'dart:async';
import '../models/message.dart';

abstract class MessagingService {
  /// Sends a message from a sender to a receiver.
  Future<void> sendMessage(Message message);

  /// Retrieves a stream of messages between the current user and the specified user.
  Stream<List<Message>> getMessagesStream(String currentUserId, String otherUserId);

  /// Marks a specific message as read.
  Future<void> markMessageAsRead(String messageId);
}

/// In-memory implementation of MessagingService for local testing and decoupled operation.
class InMemoryMessagingService implements MessagingService {
  final List<Message> _messages = [];
  final StreamController<List<Message>> _streamController = StreamController<List<Message>>.broadcast();

  List<Message> get allMessages => List.unmodifiable(_messages);

  @override
  Future<void> sendMessage(Message message) async {
    _messages.add(message);
    _streamController.add(List.unmodifiable(_messages));
  }

  @override
  Stream<List<Message>> getMessagesStream(String currentUserId, String otherUserId) {
    return _streamController.stream.map((messages) {
      return messages.where((m) {
        return (m.senderId == currentUserId && m.receiverId == otherUserId) ||
            (m.senderId == otherUserId && m.receiverId == currentUserId);
      }).toList();
    });
  }

  @override
  Future<void> markMessageAsRead(String messageId) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final old = _messages[index];
      _messages[index] = Message(
        id: old.id,
        senderId: old.senderId,
        receiverId: old.receiverId,
        content: old.content,
        timestamp: old.timestamp,
        isRead: true,
      );
      _streamController.add(List.unmodifiable(_messages));
    }
  }

  void dispose() {
    _streamController.close();
  }
}
