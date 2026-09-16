import 'package:chatly/screens/chats_screen.dart';
import 'package:chatly/screens/signin_screen.dart';
import 'package:chatly/screens/signup_screen.dart';
import 'package:chatly/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _AuthenticatedAuthService extends AuthService {
  @override
  Future<AuthenticationResult> signin({
    required String login,
    required String password,
  }) async => const Authenticated();
}

void main() {
  testWidgets('returns from sign in to sign up', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) =>
              SignupScreen(authService: _AuthenticatedAuthService()),
        ),
      ),
    );

    await tester.tap(find.text('Already registered? Sign in'));
    await tester.pumpAndSettle();

    expect(find.byType(SigninScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('signin-show-signup-button')));
    await tester.pumpAndSettle();

    expect(find.byType(SignupScreen), findsOneWidget);
    expect(find.byType(SigninScreen), findsNothing);
  });

  testWidgets('successful sign in clears previous authentication routes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SigninScreen(authService: _AuthenticatedAuthService()),
                  ),
                ),
                child: const Text('Open sign in'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(1), 'password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(ChatsScreen), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(
      Navigator.of(tester.element(find.byType(ChatsScreen))).canPop(),
      isFalse,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
