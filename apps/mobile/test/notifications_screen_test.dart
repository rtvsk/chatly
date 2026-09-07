import 'package:chatly/models/contact.dart';
import 'package:chatly/models/friend_request.dart';
import 'package:chatly/screens/notifications_screen.dart';
import 'package:chatly/services/friends_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFriendsService extends FriendsService {
  final List<FriendRequest> requests = [
    FriendRequest(
      friendshipId: 'friendship-id',
      user: const Contact(id: 'user-id', login: 'alice'),
      createdAt: DateTime.utc(2026, 9, 7),
    ),
  ];
  String? acceptedId;
  String? rejectedId;

  @override
  Future<List<FriendRequest>> getIncomingRequests() async {
    return List.unmodifiable(requests);
  }

  @override
  Future<void> acceptRequest(String friendshipId) async {
    acceptedId = friendshipId;
    requests.removeWhere((request) => request.friendshipId == friendshipId);
  }

  @override
  Future<void> rejectRequest(String friendshipId) async {
    rejectedId = friendshipId;
    requests.removeWhere((request) => request.friendshipId == friendshipId);
  }
}

void main() {
  testWidgets('accepts an incoming friend request', (tester) async {
    final service = FakeFriendsService();
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          friendsService: service,
          onNotificationsChanged: () async => changes++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.byTooltip('Accept'), findsOneWidget);
    expect(find.byTooltip('Reject'), findsOneWidget);

    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();

    expect(service.acceptedId, 'friendship-id');
    expect(changes, 1);
    expect(find.text('No notifications'), findsOneWidget);
  });

  testWidgets('rejects an incoming friend request', (tester) async {
    final service = FakeFriendsService();
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          friendsService: service,
          onNotificationsChanged: () async => changes++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Reject'));
    await tester.pumpAndSettle();

    expect(service.rejectedId, 'friendship-id');
    expect(changes, 1);
    expect(find.text('No notifications'), findsOneWidget);
  });
}
