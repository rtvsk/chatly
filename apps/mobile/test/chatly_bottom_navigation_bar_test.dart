import 'package:chatly/widgets/chatly_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSubject({
    required int selectedIndex,
    ValueChanged<int>? onDestinationSelected,
  }) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: ChatlyBottomNavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('shows all destinations and reflects the selected index', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(selectedIndex: 1));

    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navigationBar.selectedIndex, 1);
    expect(
      navigationBar.labelBehavior,
      NavigationDestinationLabelBehavior.alwaysShow,
    );
  });

  testWidgets('reports the selected destination', (tester) async {
    int? selectedIndex;
    await tester.pumpWidget(
      buildSubject(
        selectedIndex: 0,
        onDestinationSelected: (index) => selectedIndex = index,
      ),
    );

    await tester.tap(find.text('Profile'));
    await tester.pump();

    expect(selectedIndex, 2);
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
