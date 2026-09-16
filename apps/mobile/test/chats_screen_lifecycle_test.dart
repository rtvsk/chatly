import 'dart:async';

import 'package:chatly/models/avatar.dart';
import 'package:chatly/models/chat.dart';
import 'package:chatly/models/contact.dart';
import 'package:chatly/models/friend_request.dart';
import 'package:chatly/screens/chats_screen.dart';
import 'package:chatly/screens/signin_screen.dart';
import 'package:chatly/services/avatar_service.dart';
import 'package:chatly/services/chats_service.dart';
import 'package:chatly/services/contacts_service.dart';
import 'package:chatly/services/friends_service.dart';
import 'package:chatly/services/chat_realtime_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_realtime_test_support.dart';

class _EmptyContactsService extends ContactsService {
  int getFriendsCalls = 0;

  @override
  Future<List<Contact>> getFriends() async {
    getFriendsCalls += 1;
    return const [];
  }
}

class _EmptyChatsService extends ChatsService {
  int getChatsCalls = 0;

  @override
  Future<List<ChatSummary>> getChats() async {
    getChatsCalls += 1;
    return const [];
  }
}

class _UnreadChatsService extends _EmptyChatsService {
  _UnreadChatsService(this.chats);

  List<ChatSummary> chats;

  @override
  Future<List<ChatSummary>> getChats() async {
    getChatsCalls += 1;
    return chats;
  }
}

ChatSummary _unreadChat(int unreadCount) {
  return ChatSummary(
    id: 'chat-id',
    type: 'direct',
    peer: const Contact(id: 'peer-id', login: 'alice'),
    createdAt: DateTime.utc(2026, 9, 13, 9),
    updatedAt: DateTime.utc(2026, 9, 13, 10),
    unreadCount: unreadCount,
  );
}

class _EmptyFriendsService extends FriendsService {
  int incomingRequestsCalls = 0;

  @override
  Future<List<FriendRequest>> getIncomingRequests() async {
    incomingRequestsCalls += 1;
    return const [];
  }
}

class _EmptyAvatarService extends AvatarService {
  @override
  Future<List<Avatar>> getAvatars() async => const [];
}

class _BlockingFriendsService extends FriendsService {
  final initialRequest = Completer<void>();
  int incomingRequestsCalls = 0;

  @override
  Future<List<FriendRequest>> getIncomingRequests() async {
    incomingRequestsCalls += 1;
    if (incomingRequestsCalls == 1) await initialRequest.future;
    return const [];
  }
}

void main() {
  testWidgets(
    'reconnects and disconnects realtime service with app lifecycle',
    (tester) async {
      final realtime = FakeChatRealtime();
      final friendsService = _EmptyFriendsService();
      final contactsService = _EmptyContactsService();
      final chatsService = _EmptyChatsService();

      await tester.pumpWidget(
        MaterialApp(
          home: ChatsScreen(
            realtimeService: realtime,
            contactsService: contactsService,
            chatsService: chatsService,
            friendsService: friendsService,
            avatarService: _EmptyAvatarService(),
            userLoginLoader: () async => 'me',
          ),
        ),
      );
      await tester.pump();
      expect(realtime.connectCalls, 1);
      expect(friendsService.incomingRequestsCalls, 1);

      await tester.pump(const Duration(seconds: 16));
      expect(
        friendsService.incomingRequestsCalls,
        1,
        reason: 'incoming requests are not polled',
      );

      realtime.signalConnected();
      await tester.pumpAndSettle();
      expect(friendsService.incomingRequestsCalls, 2);
      expect(contactsService.getFriendsCalls, 2);
      expect(chatsService.getChatsCalls, 2);
      expect(realtime.refreshPresenceCalls, 2);

      realtime.addFriendshipChanged(FriendshipChangeType.requestCreated);
      await tester.pump();
      expect(friendsService.incomingRequestsCalls, 3);

      realtime.addFriendshipChanged(FriendshipChangeType.requestAccepted);
      await tester.pumpAndSettle();
      expect(friendsService.incomingRequestsCalls, 4);
      expect(contactsService.getFriendsCalls, 3);
      expect(chatsService.getChatsCalls, 3);
      expect(realtime.refreshPresenceCalls, 3);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(realtime.disconnectCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(realtime.disconnectCalls, 2);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(realtime.disconnectCalls, 3);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(realtime.connectCalls, 2);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(realtime.disconnectCalls, 4);
      expect(realtime.connectedCancellations, 1);
      expect(realtime.friendshipChangesCancellations, 1);
    },
  );

  testWidgets('coalesces rapid friendship events while a sync is in flight', (
    tester,
  ) async {
    final realtime = FakeChatRealtime();
    final friendsService = _BlockingFriendsService();

    await tester.pumpWidget(
      MaterialApp(
        home: ChatsScreen(
          realtimeService: realtime,
          contactsService: _EmptyContactsService(),
          chatsService: _EmptyChatsService(),
          friendsService: friendsService,
          avatarService: _EmptyAvatarService(),
          userLoginLoader: () async => 'me',
        ),
      ),
    );
    await tester.pump();
    expect(friendsService.incomingRequestsCalls, 1);

    realtime.addFriendshipChanged(FriendshipChangeType.requestCreated);
    realtime.addFriendshipChanged(FriendshipChangeType.requestRejected);
    realtime.addFriendshipChanged(FriendshipChangeType.friendRemoved);
    await tester.pump();

    friendsService.initialRequest.complete();
    await tester.pumpAndSettle();

    expect(friendsService.incomingRequestsCalls, 2);
  });

  testWidgets(
    'updates the Chats badge from realtime summaries outside the Chats tab',
    (tester) async {
      final realtime = FakeChatRealtime();
      final chatsService = _UnreadChatsService([_unreadChat(2)]);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatsScreen(
            realtimeService: realtime,
            contactsService: _EmptyContactsService(),
            chatsService: chatsService,
            friendsService: _EmptyFriendsService(),
            avatarService: _EmptyAvatarService(),
            userLoginLoader: () async => 'me',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('bottom-nav-Chats')))
            .properties
            .label,
        'Chats, 2 unread messages',
      );

      chatsService.chats = [_unreadChat(3)];
      realtime.addMessage(
        ChatMessage(
          id: 'message-id',
          chatId: 'chat-id',
          senderId: 'peer-id',
          text: 'New message',
          createdAt: DateTime.utc(2026, 9, 13, 11),
          updatedAt: DateTime.utc(2026, 9, 13, 11),
          readByPeer: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('bottom-nav-Chats')))
            .properties
            .label,
        'Chats, 3 unread messages',
      );

      await tester.tap(find.byKey(const ValueKey('bottom-nav-Chats')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('bottom-nav-Chats')))
            .properties
            .label,
        'Chats, 3 unread messages',
      );
    },
  );

  testWidgets('signs out from profile and clears the navigation stack', (
    tester,
  ) async {
    final realtime = FakeChatRealtime();
    var clearSessionCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ChatsScreen(
          realtimeService: realtime,
          contactsService: _EmptyContactsService(),
          chatsService: _EmptyChatsService(),
          friendsService: _EmptyFriendsService(),
          avatarService: _EmptyAvatarService(),
          userLoginLoader: () async => 'me',
          sessionClearer: () async => clearSessionCalls++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final appBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(appBar.automaticallyImplyLeading, isFalse);
    expect(appBar.actions, isNull);

    await tester.tap(find.byKey(const ValueKey('bottom-nav-Profile')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('profile-sign-out')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-sign-out')));
    await tester.pumpAndSettle();

    expect(clearSessionCalls, 1);
    expect(realtime.disconnectCalls, greaterThanOrEqualTo(1));
    expect(find.byType(SigninScreen), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(SigninScreen))).canPop(),
      isFalse,
    );
  });
}
