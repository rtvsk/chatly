import 'package:chatly/models/contact.dart';
import 'package:chatly/screens/chats_screen.dart';
import 'package:chatly/services/contacts_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeContactsService extends ContactsService {
  FakeContactsService({this.friends = const [], this.searchResults = const {}});

  final List<Contact> friends;
  final Map<String, List<Contact>> searchResults;
  final List<String> searchCalls = [];

  @override
  Future<List<Contact>> getFriends() async => friends;

  @override
  Future<List<Contact>> searchUsers(String login) async {
    searchCalls.add(login);
    return searchResults[login] ?? const [];
  }
}

Widget _appWith(FakeContactsService service) {
  return MaterialApp(
    home: Scaffold(body: ContactsTab(contactsService: service)),
  );
}

void main() {
  testWidgets('shows real friends returned by the service', (tester) async {
    final service = FakeContactsService(
      friends: const [
        Contact(id: 'one', login: 'alice'),
        Contact(id: 'two', login: 'bob'),
      ],
    );

    await tester.pumpWidget(_appWith(service));
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Contact 0'), findsNothing);
  });

  testWidgets('shows an empty state when the user has no friends', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(FakeContactsService()));
    await tester.pumpAndSettle();

    expect(find.text('No contacts'), findsOneWidget);
  });

  testWidgets('searches after three characters and a debounce delay', (
    tester,
  ) async {
    final service = FakeContactsService(
      searchResults: const {
        'ale': [
          Contact(
            id: 'result',
            login: 'alex',
            avatarUrl: '/avatars/avatar-id/file',
          ),
        ],
      },
    );
    await tester.pumpWidget(_appWith(service));
    await tester.pumpAndSettle();

    final searchField = find.byKey(const Key('contacts-search-field'));
    await tester.enterText(searchField, 'al');
    await tester.pump(const Duration(milliseconds: 500));
    expect(service.searchCalls, isEmpty);

    await tester.enterText(searchField, 'ale');
    await tester.pump(const Duration(milliseconds: 399));
    expect(service.searchCalls, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(service.searchCalls, ['ale']);
    expect(find.text('alex'), findsOneWidget);
    final avatar = tester.widget<CircleAvatar>(
      find.byKey(const Key('contact-avatar-result')),
    );
    final image = avatar.foregroundImage! as NetworkImage;
    expect(image.url, 'http://localhost:3000/avatars/avatar-id/file');
  });

  testWidgets(
    'shows an empty search state and restores contacts when cleared',
    (tester) async {
      final service = FakeContactsService(
        friends: const [Contact(id: 'friend', login: 'charlie')],
      );
      await tester.pumpWidget(_appWith(service));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('contacts-search-field')),
        'nobody',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('No users found'), findsOneWidget);
      expect(find.text('charlie'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();

      expect(find.text('charlie'), findsOneWidget);
      expect(find.text('No users found'), findsNothing);
    },
  );
}
