import 'package:chatly/services/friends_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('removes a friend when the API returns 204', () async {
    late http.Request request;

    await http.runWithClient(
      () => FriendsService().removeFriend('friend-id'),
      () => MockClient((received) async {
        request = received;
        return http.Response('', 204);
      }),
    );

    expect(request.method, 'DELETE');
    expect(request.url.path, '/friends/friend-id');
  });

  test('throws when removing a friend fails', () async {
    await expectLater(
      http.runWithClient(
        () => FriendsService().removeFriend('friend-id'),
        () => MockClient((_) async => http.Response('', 404)),
      ),
      throwsException,
    );
  });
}
