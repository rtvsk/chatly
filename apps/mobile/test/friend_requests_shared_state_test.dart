import 'package:chatly/models/avatar.dart';
import 'package:chatly/models/chat.dart';
import 'package:chatly/models/contact.dart';
import 'package:chatly/models/friend_request.dart';
import 'package:chatly/screens/chats_screen.dart';
import 'package:chatly/services/avatar_service.dart';
import 'package:chatly/services/chats_service.dart';
import 'package:chatly/services/contacts_service.dart';
import 'package:chatly/services/friends_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_realtime_test_support.dart';

class _RequestsFriendsService extends FriendsService {
  int calls = 0;

  @override
  Future<List<FriendRequest>> getIncomingRequests() async {
    calls += 1;
    return [
      FriendRequest(
        friendshipId: 'friendship-id',
        user: const Contact(id: 'alice-id', login: 'alice'),
        createdAt: DateTime.utc(2026, 9, 13),
      ),
    ];
  }
}

class _EmptyContactsService extends ContactsService {
  @override
  Future<List<Contact>> getFriends() async => const [];
}

class _EmptyChatsService extends ChatsService {
  @override
  Future<List<ChatSummary>> getChats() async => const [];
}

class _EmptyAvatarService extends AvatarService {
  @override
  Future<List<Avatar>> getAvatars() async => const [];
}

void main() {
  testWidgets('badge and notifications list share the already-synced state', (
    tester,
  ) async {
    final friendsService = _RequestsFriendsService();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatsScreen(
          realtimeService: FakeChatRealtime(),
          friendsService: friendsService,
          contactsService: _EmptyContactsService(),
          chatsService: _EmptyChatsService(),
          avatarService: _EmptyAvatarService(),
          userLoginLoader: () async => 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Profile, 1 notifications'), findsOneWidget);
    expect(friendsService.calls, 1);

    await tester.tap(find.byKey(const ValueKey('bottom-nav-Profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(
      friendsService.calls,
      1,
      reason: 'opening NotificationsScreen does not issue a separate GET',
    );
  });
}
