import 'package:chatly/models/chat.dart';
import 'package:chatly/models/contact.dart';
import 'package:chatly/screens/chat_screen.dart';
import 'package:chatly/services/chats_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_realtime_test_support.dart';

class FakeChatsService extends ChatsService {
  FakeChatsService({this.messages = const [], this.markReadFails = false});

  List<ChatMessage> messages;
  String? sentText;
  final List<String?> afterCalls = [];
  final List<String> markedReadMessageIds = [];
  bool markReadFails;

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

  @override
  Future<void> markRead(String chatId, String messageId) async {
    markedReadMessageIds.add(messageId);
    if (markReadFails) throw Exception('failed');
  }
}

final _chat = ChatSummary(
  id: 'chat-id',
  type: 'direct',
  peer: const Contact(id: 'peer-id', login: 'alice'),
  createdAt: DateTime.utc(2026, 9, 13, 9),
  updatedAt: DateTime.utc(2026, 9, 13, 10),
  unreadCount: 0,
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

    service.messages = const [];
    realtime.signalConnected();
    await tester.pumpAndSettle();
    expect(service.afterCalls.last, 'realtime-id');
    expect(service.markedReadMessageIds, ['initial-id', 'realtime-id']);
  });

  testWidgets('keeps loaded messages visible when marking them read fails', (
    tester,
  ) async {
    final service = FakeChatsService(
      markReadFails: true,
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

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(chat: _chat, chatsService: service),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hello'), findsOneWidget);
    expect(service.markedReadMessageIds, ['peer-message']);
  });

  testWidgets('shows and clears the peer online status from presence updates', (
    tester,
  ) async {
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

    expect(find.text('Online'), findsNothing);
    expect(find.byKey(const Key('chat-peer-online-indicator')), findsNothing);
    expect(realtime.refreshPresenceCalls, 1);

    realtime.applyPresenceSnapshot(const ['peer-id']);
    await tester.pumpAndSettle();
    expect(find.text('Online'), findsOneWidget);
    expect(find.byKey(const Key('chat-peer-online-indicator')), findsOneWidget);

    realtime.applyPresenceChanged(userId: 'peer-id', isOnline: false);
    await tester.pumpAndSettle();
    expect(find.text('Online'), findsNothing);
    expect(find.byKey(const Key('chat-peer-online-indicator')), findsNothing);
  });

  testWidgets('shows peer typing, restores Online, and expires stale typing', (
    tester,
  ) async {
    final realtime = FakeChatRealtime(onlineUserIds: const ['peer-id']);

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

    expect(find.text('Online'), findsOneWidget);
    realtime.addTypingChanged(userId: 'peer-id', isTyping: true);
    await tester.pumpAndSettle();
    expect(find.text('typing'), findsOneWidget);
    expect(find.text('Online'), findsNothing);
    expect(find.byKey(const Key('chat-peer-online-indicator')), findsOneWidget);

    realtime.addTypingChanged(userId: 'peer-id', isTyping: false);
    await tester.pumpAndSettle();
    expect(find.text('Online'), findsOneWidget);

    realtime.addTypingChanged(userId: 'peer-id', isTyping: true);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Online'), findsOneWidget);
  });

  testWidgets('clears peer typing when the peer goes offline', (tester) async {
    final realtime = FakeChatRealtime(onlineUserIds: const ['peer-id']);

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

    realtime.addTypingChanged(userId: 'peer-id', isTyping: true);
    await tester.pumpAndSettle();
    expect(find.text('typing'), findsOneWidget);

    realtime.applyPresenceChanged(userId: 'peer-id', isOnline: false);
    await tester.pumpAndSettle();
    expect(find.text('typing'), findsNothing);
    expect(find.text('Online'), findsNothing);
  });

  testWidgets('emits typing true and false after inactivity and sending', (
    tester,
  ) async {
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

    await tester.enterText(find.byKey(const Key('chat-message-field')), 'Hi');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byKey(const Key('chat-message-field')), 'Hi!');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(realtime.setTypingCalls.map((event) => event.isTyping), [
      true,
      true,
    ]);
    await tester.pump(const Duration(seconds: 1));
    expect(realtime.setTypingCalls.map((event) => event.isTyping), [
      true,
      true,
      false,
    ]);

    await tester.enterText(
      find.byKey(const Key('chat-message-field')),
      'Sending now',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-message-button')));
    await tester.pumpAndSettle();
    expect(realtime.setTypingCalls.map((event) => event.isTyping), [
      true,
      true,
      false,
      true,
      false,
    ]);
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
    await tester.enterText(find.byKey(const Key('chat-message-field')), 'Hi');
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));

    expect(realtime.messageCancellations, 1);
    expect(realtime.typingChangesCancellations, 1);
    expect(realtime.connectedCancellations, 1);
    expect(realtime.onlineUserIdsCancellations, 1);
    expect(realtime.setTypingCalls.map((event) => event.isTyping), [
      true,
      false,
    ]);
  });
}
