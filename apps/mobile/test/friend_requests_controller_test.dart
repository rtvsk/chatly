import 'dart:async';

import 'package:chatly/models/friend_request.dart';
import 'package:chatly/services/friend_requests_controller.dart';
import 'package:chatly/services/friends_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _BlockingFriendsService extends FriendsService {
  final gate = Completer<void>();
  int calls = 0;

  @override
  Future<List<FriendRequest>> getIncomingRequests() async {
    calls += 1;
    if (calls == 1) await gate.future;
    return const [];
  }
}

void main() {
  test('coalesces rapid refreshes into one queued rerun', () async {
    final service = _BlockingFriendsService();
    final controller = FriendRequestsController(friendsService: service);

    final first = controller.refresh();
    final second = controller.refresh();
    final third = controller.refresh();
    expect(service.calls, 1);

    service.gate.complete();
    await Future.wait([first, second, third]);

    expect(service.calls, 2);
    controller.dispose();
  });
}
