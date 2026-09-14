import 'dart:convert';

import 'package:chatly/services/chats_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('marks a chat message read with the agreed PATCH contract', () async {
    late http.Request request;

    await http.runWithClient(
      () => ChatsService().markRead('chat-id', 'message-id'),
      () => MockClient((received) async {
        request = received;
        return http.Response('', 204);
      }),
    );

    expect(request.method, 'PATCH');
    expect(request.url.path, '/chats/chat-id/read');
    expect(jsonDecode(request.body), {'messageId': 'message-id'});
  });

  test('throws when marking a chat message read fails', () async {
    await expectLater(
      http.runWithClient(
        () => ChatsService().markRead('chat-id', 'message-id'),
        () => MockClient((_) async => http.Response('', 404)),
      ),
      throwsException,
    );
  });
}
