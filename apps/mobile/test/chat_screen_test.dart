import 'package:chatly/models/chat.dart';
import 'package:chatly/models/contact.dart';
import 'package:chatly/screens/chat_screen.dart';
import 'package:chatly/services/chats_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_realtime_test_support.dart';

class FakeChatsService extends ChatsService {
  FakeChatsService({this.messages = const []});

  List<ChatMessage> messages;
  String? sentText;
  final List<String?> afterCalls = [];

  @override
  Future<List<ChatMessage>> getMessages(String chatId, {String? after}) async {
    afterCalls.add(after);
    return messages;
  }

  @override
  Future<ChatMessage> sendMessage(String chatId, String text) async {
    sentText = text;
    return ChatMessage(
      id: 'sent-id',
      chatId: chatId,
      senderId: 'current-user-id',
      text: text,
      createdAt: DateTime.utc(2026, 9, 13, 11),
      updatedAt: DateTime.utc(2026, 9, 13, 11),
    );
  }
}

final _chat = ChatSummary(
  id: 'chat-id',
  type: 'direct',
  peer: const Contact(id: 'peer-id', login: 'alice'),
  createdAt: DateTime.utc(2026, 9, 13, 9),
  updatedAt: DateTime.utc(2026, 9, 13, 10),
);

void main() {
  testWidgets('loads messages and appends a confirmed sent message', (
    tester,
  ) async {
    final service = FakeChatsService(
      messages: [
        ChatMessage(
          id: 'peer-message',
          chatId: 'chat-id',
          senderId: 'peer-id',
          text: 'Hello',
          createdAt: DateTime.utc(2026, 9, 13, 10),
          updatedAt: DateTime.utc(2026, 9, 13, 10),
        ),
      ],
    );
    final realtime = FakeChatRealtime();

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          chat: _chat,
          chatsService: service,
          realtimeService: realtime,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('chat-message-field')),
      'Hi Alice',
    );
    await tester.tap(find.byKey(const Key('send-message-button')));
    await tester.pumpAndSettle();

    expect(service.sentText, 'Hi Alice');
    expect(find.text('Hi Alice'), findsOneWidget);
    expect(find.byKey(const Key('message-sent-id')), findsOneWidget);
  });

  testWidgets('filters, deduplicates and catches up realtime messages', (
    tester,
  ) async {
    final service = FakeChatsService(
      messages: [
        ChatMessage(
          id: 'initial-id',
          chatId: 'chat-id',
          senderId: 'peer-id',
          text: 'Initial message',
          createdAt: DateTime.utc(2026, 9, 13, 10),
          updatedAt: DateTime.utc(2026, 9, 13, 10),
        ),
      ],
    );
    final realtime = FakeChatRealtime();
    final incoming = ChatMessage(
      id: 'realtime-id',
      chatId: 'chat-id',
      senderId: 'peer-id',
      text: 'Realtime message',
      createdAt: DateTime.utc(2026, 9, 13, 11),
      updatedAt: DateTime.utc(2026, 9, 13, 11),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          chat: _chat,
          chatsService: service,
          realtimeService: realtime,
        ),
      ),
    );
    await tester.pumpAndSettle();

    realtime.addMessage(
      ChatMessage(
        id: 'another-chat-message',
        chatId: 'another-chat',
        senderId: 'peer-id',
        text: 'Wrong chat',
        createdAt: DateTime.utc(2026, 9, 13, 11),
        updatedAt: DateTime.utc(2026, 9, 13, 11),
      ),
    );
    await tester.pump();
    expect(find.text('Wrong chat'), findsNothing);

    realtime.addMessage(incoming);
    await tester.pumpAndSettle();
    expect(find.text('Realtime message'), findsOneWidget);

    realtime.addMessage(incoming);
    await tester.pumpAndSettle();
    expect(find.text('Realtime message'), findsOneWidget);

    realtime.signalConnected();
    await tester.pumpAndSettle();
    expect(service.afterCalls.last, 'realtime-id');
  });

  testWidgets('cancels realtime subscriptions when disposed', (tester) async {
    final realtime = FakeChatRealtime();

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          chat: _chat,
          chatsService: FakeChatsService(),
          realtimeService: realtime,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(realtime.messageCancellations, 1);
    expect(realtime.connectedCancellations, 1);
  });
}
