import 'package:chatly/screens/signup_screen.dart';
import 'package:chatly/screens/signin_screen.dart';
import 'package:chatly/screens/verify_email_screen.dart';
import 'package:chatly/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthService extends AuthService {
  int resendCalls = 0;

  @override
  Future<bool> resendVerification({required String email}) async {
    resendCalls++;
    return true;
  }
}

class UnverifiedAuthService extends AuthService {
  @override
  Future<AuthenticationResult> signin({
    required String login,
    required String password,
  }) async {
    return VerificationRequired(email: 'alice@example.com', login: login);
  }
}

class SignupVerificationAuthService extends AuthService {
  SignupVerificationAuthService(this.delivery);

  final String delivery;

  @override
  Future<SignupResult> signup({
    required String login,
    required String email,
    required String password,
    required String repeatPassword,
  }) async {
    return SignupVerificationRequired(
      email: email,
      delivery: delivery,
      login: login,
    );
  }
}

void main() {
  testWidgets('shows email, pending delivery, and resend cooldown', (
    tester,
  ) async {
    final authService = FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(
        home: VerifyEmailScreen(
          email: 'alice@example.com',
          delivery: 'pending',
          login: 'alice',
          authService: authService,
        ),
      ),
    );

    expect(
      find.text('Please Verify Your Email alice@example.com'),
      findsOneWidget,
    );
    expect(
      find.text(
        'We could not send the verification email yet. Please resend it.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('resend-verification-button')));
    await tester.pump();

    expect(authService.resendCalls, 1);
    expect(find.text('Verification email sent.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('resend-verification-button')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Resend in 60 s'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('signup validates the email field before submitting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: FakeAuthService())),
    );

    final emailField = tester.widget<TextField>(
      find.byKey(const Key('signup-email-field')),
    );
    expect(emailField.keyboardType, TextInputType.emailAddress);

    await tester.enterText(
      find.byKey(const Key('signup-email-field')),
      'not-email',
    );
    await tester.tap(find.text('Sign up'));
    await tester.pump();

    expect(find.text('Please fill in all fields'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(2), 'password');
    await tester.enterText(find.byType(TextField).at(3), 'password');
    await tester.tap(find.text('Sign up'));
    await tester.pump();

    expect(find.text('Please enter a valid email address'), findsOneWidget);
    expect(isValidEmail('alice@example.com'), isTrue);
    expect(isValidEmail('not-email'), isFalse);
  });

  for (final delivery in ['pending', 'sent']) {
    testWidgets(
      'successful signup opens verification screen with $delivery delivery',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SignupScreen(
              authService: SignupVerificationAuthService(delivery),
            ),
          ),
        );

        await tester.enterText(find.byType(TextField).at(0), 'alice');
        await tester.enterText(
          find.byKey(const Key('signup-email-field')),
          'alice@example.com',
        );
        await tester.enterText(find.byType(TextField).at(2), 'password');
        await tester.enterText(find.byType(TextField).at(3), 'password');
        await tester.tap(find.widgetWithText(FilledButton, 'Sign up'));
        await tester.pumpAndSettle();

        expect(
          find.text('Please Verify Your Email alice@example.com'),
          findsOneWidget,
        );
        expect(
          find.text(
            delivery == 'pending'
                ? 'We could not send the verification email yet. Please resend it.'
                : 'A verification email has been sent.',
          ),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('unverified sign in opens the verification screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SigninScreen(authService: UnverifiedAuthService())),
    );

    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(1), 'password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(
      find.text('Please Verify Your Email alice@example.com'),
      findsOneWidget,
    );
  });

  testWidgets('back to sign in preserves the known login', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VerifyEmailScreen(email: 'alice@example.com', login: 'alice'),
      ),
    );

    await tester.tap(find.text('Back to Sign in'));
    await tester.pumpAndSettle();

    final loginField = tester.widget<TextField>(find.byType(TextField).first);
    expect(loginField.controller!.text, 'alice');
  });
}
