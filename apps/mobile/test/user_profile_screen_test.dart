import 'package:chatly/models/contact.dart';
import 'package:chatly/models/friend_request.dart';
import 'package:chatly/models/chat.dart';
import 'package:chatly/screens/user_profile_screen.dart';
import 'package:chatly/services/chats_service.dart';
import 'package:chatly/services/friends_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFriendsService extends FriendsService {
  String? requestedUserId;
  String? removedUserId;
  FriendshipState friendshipState;
  bool shouldFailRemoval;

  FakeFriendsService({
    this.friendshipState = FriendshipState.none,
    this.shouldFailRemoval = false,
  });

  @override
  Future<FriendshipState> getFriendshipStatus(String userId) async {
    return friendshipState;
  }

  @override
  Future<void> sendRequest(String receiverId) async {
    requestedUserId = receiverId;
  }

  @override
  Future<void> removeFriend(String userId) async {
    if (shouldFailRemoval) throw Exception('request failed');
    removedUserId = userId;
  }
}

class FakeChatsService extends ChatsService {
  @override
  Future<ChatSummary?> getDirectChat(String userId) async => null;
}

Widget _profileApp(FriendsService service, {ValueChanged<bool?>? onResult}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(
                    user: const Contact(id: 'user-id', login: 'dima'),
                    friendsService: service,
                    chatsService: FakeChatsService(),
                  ),
                ),
              );
              onResult?.call(result);
            },
            child: const Text('Open profile'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the user and sends a friend request', (tester) async {
    final service = FakeFriendsService();
    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen(
          user: const Contact(
            id: 'user-id',
            login: 'dima',
            avatarUrl: '/avatars/avatar-id/file',
          ),
          friendsService: service,
          chatsService: FakeChatsService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('dima'), findsOneWidget);
    final avatar = tester.widget<CircleAvatar>(
      find.byKey(const Key('user-profile-avatar')),
    );
    expect(avatar.radius, 76);
    expect(find.text('Add friend'), findsOneWidget);

    await tester.tap(find.text('Add friend'));
    await tester.pumpAndSettle();

    expect(service.requestedUserId, 'user-id');
    expect(find.text('Request sent'), findsOneWidget);
  });

  testWidgets('cancelling removal leaves the friendship unchanged', (
    tester,
  ) async {
    final service = FakeFriendsService(
      friendshipState: FriendshipState.friends,
    );
    await tester.pumpWidget(_profileApp(service));

    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove-friend-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('This will also delete your shared chat and its history.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(service.removedUserId, isNull);
    expect(find.byKey(const Key('remove-friend-button')), findsOneWidget);
  });

  testWidgets('accepted friends can start a chat without losing removal', (
    tester,
  ) async {
    final service = FakeFriendsService(
      friendshipState: FriendshipState.friends,
    );
    await tester.pumpWidget(_profileApp(service));

    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();

    expect(find.text('Start chat'), findsOneWidget);
    expect(find.byKey(const Key('remove-friend-button')), findsOneWidget);
  });

  testWidgets('removing a friend pops with a reload signal', (tester) async {
    final service = FakeFriendsService(
      friendshipState: FriendshipState.friends,
    );
    bool? result;
    await tester.pumpWidget(
      _profileApp(service, onResult: (value) => result = value),
    );

    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove-friend-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-remove-friend')));
    await tester.pumpAndSettle();

    expect(service.removedUserId, 'user-id');
    expect(result, isTrue);
    expect(find.text('Open profile'), findsOneWidget);
  });

  testWidgets('failed removal keeps the friend state and shows an error', (
    tester,
  ) async {
    final service = FakeFriendsService(
      friendshipState: FriendshipState.friends,
      shouldFailRemoval: true,
    );
    await tester.pumpWidget(_profileApp(service));

    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove-friend-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-remove-friend')));
    await tester.pumpAndSettle();

    expect(find.text('Could not remove friend'), findsOneWidget);
    expect(find.byKey(const Key('remove-friend-button')), findsOneWidget);
  });
}
