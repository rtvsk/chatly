import 'package:chatly/models/chat.dart';
import 'package:chatly/models/contact.dart';
import 'package:chatly/screens/chats_screen.dart';
import 'package:chatly/services/chats_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeChatsService extends ChatsService {
  FakeChatsService({this.chats = const [], this.shouldFail = false});

  List<ChatSummary> chats;
  bool shouldFail;
  int calls = 0;

  @override
  Future<List<ChatSummary>> getChats() async {
    calls += 1;
    if (shouldFail) throw Exception('failed');
    return chats;
  }
}

ChatSummary _chat({ChatMessage? lastMessage}) {
  return ChatSummary(
    id: 'chat-id',
    type: 'direct',
    peer: const Contact(id: 'peer-id', login: 'alice'),
    lastMessage: lastMessage,
    createdAt: DateTime.utc(2026, 9, 13, 9),
    updatedAt: DateTime.utc(2026, 9, 13, 10),
  );
}

void main() {
  Widget app(FakeChatsService service) => MaterialApp(
    home: Scaffold(body: ChatsTab(chatsService: service)),
  );

  testWidgets('shows direct chats returned by the service', (tester) async {
    final service = FakeChatsService(
      chats: [
        _chat(
          lastMessage: ChatMessage(
            id: 'message-id',
            chatId: 'chat-id',
            senderId: 'peer-id',
            text: 'Last message',
            createdAt: DateTime.utc(2026, 9, 13, 10),
            updatedAt: DateTime.utc(2026, 9, 13, 10),
          ),
        ),
      ],
    );

    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('Last message'), findsOneWidget);
  });

  testWidgets('shows a retryable error state', (tester) async {
    final service = FakeChatsService(shouldFail: true);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();

    expect(find.text('Could not load chats'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(service.calls, 2);
  });
}
