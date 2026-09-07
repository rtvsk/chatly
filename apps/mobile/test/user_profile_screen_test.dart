import 'package:chatly/models/contact.dart';
import 'package:chatly/models/friend_request.dart';
import 'package:chatly/screens/user_profile_screen.dart';
import 'package:chatly/services/friends_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFriendsService extends FriendsService {
  String? requestedUserId;

  @override
  Future<FriendshipState> getFriendshipStatus(String userId) async {
    return FriendshipState.none;
  }

  @override
  Future<void> sendRequest(String receiverId) async {
    requestedUserId = receiverId;
  }
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
}
