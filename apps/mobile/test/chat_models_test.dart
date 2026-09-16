import 'package:chatly/models/chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses direct chat summaries with an optional last message', () {
    final chat = ChatSummary.fromJson({
      'id': 'chat-id',
      'type': 'direct',
      'peer': {'id': 'peer-id', 'login': 'alice', 'avatarUrl': null},
      'lastMessage': {
        'id': 'message-id',
        'chatId': 'chat-id',
        'senderId': 'peer-id',
        'text': 'Hello',
        'createdAt': '2026-09-13T10:00:00.000Z',
        'updatedAt': '2026-09-13T10:00:00.000Z',
        'readByPeer': false,
      },
      'createdAt': '2026-09-13T09:00:00.000Z',
      'updatedAt': '2026-09-13T10:00:00.000Z',
      'unreadCount': 2,
    });

    expect(chat.type, 'direct');
    expect(chat.peer.login, 'alice');
    expect(chat.lastMessage?.text, 'Hello');
    expect(chat.lastMessage?.createdAt, DateTime.utc(2026, 9, 13, 10));
    expect(chat.unreadCount, 2);
  });

  test('parses messages returned after the current cursor', () {
    final message = ChatMessage.fromJson({
      'id': 'message-id',
      'chatId': 'chat-id',
      'senderId': 'sender-id',
      'text': 'A message',
      'createdAt': '2026-09-13T10:00:00.000Z',
      'updatedAt': '2026-09-13T10:01:00.000Z',
      'readByPeer': true,
    });

    expect(message.chatId, 'chat-id');
    expect(message.senderId, 'sender-id');
    expect(message.updatedAt, DateTime.utc(2026, 9, 13, 10, 1));
    expect(message.readByPeer, isTrue);
  });
}
