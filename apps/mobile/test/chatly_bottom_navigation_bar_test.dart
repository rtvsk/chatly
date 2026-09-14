import 'package:chatly/widgets/chatly_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSubject({
    required int selectedIndex,
    int profileBadgeCount = 0,
    int chatBadgeCount = 0,
    ValueChanged<int>? onDestinationSelected,
  }) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: ChatlyBottomNavigationBar(
          selectedIndex: selectedIndex,
          chatBadgeCount: chatBadgeCount,
          profileBadgeCount: profileBadgeCount,
          onDestinationSelected: onDestinationSelected ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('shows large icons without visible labels', (tester) async {
    await tester.pumpWidget(buildSubject(selectedIndex: 1));

    expect(find.text('Contacts'), findsNothing);
    expect(find.text('Chats'), findsNothing);
    expect(find.text('Profile'), findsNothing);
    expect(find.byIcon(Icons.group_outlined), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_rounded), findsOneWidget);
    expect(find.byIcon(Icons.account_circle_outlined), findsOneWidget);

    final selectedIcon = tester.widget<Icon>(
      find.byIcon(Icons.chat_bubble_rounded),
    );
    expect(selectedIcon.size, 30);

    expect(
      tester
          .getSize(find.byKey(const ValueKey('bottom-nav-capsule-Chats')))
          .height,
      52,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('bottom-nav-capsule-Chats')))
          .width,
      52,
    );

    final selectedTab = tester.widget<Semantics>(
      find.byKey(const ValueKey('bottom-nav-Chats')),
    );
    expect(selectedTab.properties.selected, isTrue);
    expect(selectedTab.properties.label, 'Chats');
  });

  testWidgets('reports the selected destination', (tester) async {
    int? selectedIndex;
    await tester.pumpWidget(
      buildSubject(
        selectedIndex: 0,
        onDestinationSelected: (index) => selectedIndex = index,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('bottom-nav-Profile')));
    await tester.pump();

    expect(selectedIndex, 2);
  });

  testWidgets('shows the notification count on the profile destination', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(selectedIndex: 0, profileBadgeCount: 3),
    );

    expect(find.text('3'), findsOneWidget);
    final badge = tester.widget<Badge>(find.byType(Badge).last);
    expect(badge.backgroundColor, Colors.red);
  });

  testWidgets('shows unread messages on Chats with an accessible label', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(selectedIndex: 0, chatBadgeCount: 12));

    expect(find.text('12'), findsOneWidget);
    final chatsTab = tester.widget<Semantics>(
      find.byKey(const ValueKey('bottom-nav-Chats')),
    );
    expect(chatsTab.properties.label, 'Chats, 12 unread messages');
    final badge = tester.widget<Badge>(find.byKey(const ValueKey('false-12')));
    expect(badge.backgroundColor, Colors.red);
  });

  testWidgets('does not show a Chats badge when there are no unread messages', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(selectedIndex: 1));

    final chatsTab = tester.widget<Semantics>(
      find.byKey(const ValueKey('bottom-nav-Chats')),
    );
    expect(chatsTab.properties.label, 'Chats');
    final badge = tester.widget<Badge>(find.byKey(const ValueKey('true-0')));
    expect(badge.isLabelVisible, isFalse);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('keeps hidden destinations accessible', (tester) async {
    await tester.pumpWidget(buildSubject(selectedIndex: 1));

    final contactsTab = tester.widget<Semantics>(
      find.byKey(const ValueKey('bottom-nav-Contacts')),
    );
    final profileTab = tester.widget<Semantics>(
      find.byKey(const ValueKey('bottom-nav-Profile')),
    );

    expect(contactsTab.properties.label, 'Contacts');
    expect(contactsTab.properties.button, isTrue);
    expect(contactsTab.properties.selected, isFalse);
    expect(profileTab.properties.label, 'Profile');
    expect(profileTab.properties.button, isTrue);
    Finder tooltipWithMessage(String message) {
      return find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == message,
      );
    }

    expect(tooltipWithMessage('Contacts'), findsOneWidget);
    expect(tooltipWithMessage('Profile'), findsOneWidget);
    expect(tooltipWithMessage('Chats'), findsOneWidget);
  });

  testWidgets('fits a narrow screen and respects the safe area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildSubject(selectedIndex: 0));

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SafeArea &&
            widget.minimum == const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
