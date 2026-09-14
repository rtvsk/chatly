import 'package:chatly/models/friend_request.dart';
import 'package:chatly/screens/profile_screen.dart';
import 'package:chatly/services/friends_service.dart';
import 'package:chatly/services/friend_requests_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class EmptyFriendsService extends FriendsService {
  @override
  Future<List<FriendRequest>> getIncomingRequests() async => const [];
}

void main() {
  testWidgets('shows links for avatars and notifications', (tester) async {
    final friendsService = EmptyFriendsService();
    final friendRequests = FriendRequestsController(
      friendsService: friendsService,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileTab(
            login: 'current-user',
            friendsService: friendsService,
            friendRequests: friendRequests,
            onAvatarsChanged: () async {},
            onNotificationsChanged: () async {},
            onSignOut: () async {},
          ),
        ),
      ),
    );

    expect(find.text('Set up avatars'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Add avatar'), findsNothing);

    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Notifications'), findsOneWidget);
    expect(find.text('No notifications'), findsOneWidget);
    friendRequests.dispose();
  });

  testWidgets('confirms before signing out', (tester) async {
    final friendsService = EmptyFriendsService();
    final friendRequests = FriendRequestsController(
      friendsService: friendsService,
    );
    var signOutCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileTab(
            login: 'current-user',
            friendsService: friendsService,
            friendRequests: friendRequests,
            onAvatarsChanged: () async {},
            onNotificationsChanged: () async {},
            onSignOut: () async => signOutCalls++,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('profile-sign-out')), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-sign-out')));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(signOutCalls, 0);

    await tester.tap(find.byKey(const Key('profile-sign-out')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-sign-out')));
    await tester.pumpAndSettle();
    expect(signOutCalls, 1);

    friendRequests.dispose();
  });
}
