import 'package:chatly/navigation/app_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('replaces the navigation stack with signup', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: AppNavigation.navigatorKey,
        routes: {
          AppNavigation.signupRoute: (_) =>
              const Scaffold(body: Text('Signup screen')),
        },
        home: const Scaffold(body: Text('Authenticated screen')),
      ),
    );

    AppNavigation.showSignup();
    await tester.pumpAndSettle();

    expect(find.text('Signup screen'), findsOneWidget);
    expect(find.text('Authenticated screen'), findsNothing);
    expect(AppNavigation.navigatorKey.currentState!.canPop(), isFalse);
  });
}
