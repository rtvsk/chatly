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

class _EmptyContactsService extends ContactsService {
  @override
  Future<List<Contact>> getFriends() async => const [];
}

class _EmptyChatsService extends ChatsService {
  @override
  Future<List<ChatSummary>> getChats() async => const [];
}

class _EmptyFriendsService extends FriendsService {
  @override
  Future<List<FriendRequest>> getIncomingRequests() async => const [];
}

class _EmptyAvatarService extends AvatarService {
  @override
  Future<List<Avatar>> getAvatars() async => const [];
}

void main() {
  testWidgets(
    'reconnects and disconnects realtime service with app lifecycle',
    (tester) async {
      final realtime = FakeChatRealtime();

      await tester.pumpWidget(
        MaterialApp(
          home: ChatsScreen(
            realtimeService: realtime,
            contactsService: _EmptyContactsService(),
            chatsService: _EmptyChatsService(),
            friendsService: _EmptyFriendsService(),
            avatarService: _EmptyAvatarService(),
            userLoginLoader: () async => 'me',
          ),
        ),
      );
      await tester.pump();
      expect(realtime.connectCalls, 1);

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
    },
  );
}
