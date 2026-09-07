import 'package:chatly/models/friend_request.dart';
import 'package:chatly/screens/profile_screen.dart';
import 'package:chatly/services/friends_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class EmptyFriendsService extends FriendsService {
  @override
  Future<List<FriendRequest>> getIncomingRequests() async => const [];
}

void main() {
  testWidgets('shows links for avatars and notifications', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileTab(
            login: 'current-user',
            friendsService: EmptyFriendsService(),
            onAvatarsChanged: () async {},
            onNotificationsChanged: () async {},
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
  });
}
