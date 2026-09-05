import 'package:chatly/models/avatar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses avatar metadata returned by the API', () {
    final avatar = Avatar.fromJson({
      'id': 'avatar-id',
      'originalName': 'me.png',
      'mimeType': 'image/png',
      'size': 1024,
      'isSelected': true,
      'createdAt': '2026-09-05T12:00:00.000Z',
      'url': '/avatars/avatar-id/file',
    });

    expect(avatar.id, 'avatar-id');
    expect(avatar.mimeType, 'image/png');
    expect(avatar.size, 1024);
    expect(avatar.isSelected, isTrue);
    expect(avatar.createdAt, DateTime.utc(2026, 9, 5, 12));
    expect(avatar.url, '/avatars/avatar-id/file');
  });
}
