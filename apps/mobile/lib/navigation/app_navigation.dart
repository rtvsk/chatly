import 'package:flutter/material.dart';

import '../screens/verify_email_screen.dart';

class AppNavigation {
  AppNavigation._();

  static const signupRoute = '/signup';
  static final navigatorKey = GlobalKey<NavigatorState>();

  static bool _redirectScheduled = false;

  static void showSignup() {
    if (_redirectScheduled) return;

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    _redirectScheduled = true;
    navigator.pushNamedAndRemoveUntil(signupRoute, (_) => false);
    Future.microtask(() {
      _redirectScheduled = false;
    });
  }

  static void showVerification({required String email, String? login}) {
    if (_redirectScheduled) return;

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    _redirectScheduled = true;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => VerifyEmailScreen(email: email, login: login),
      ),
      (_) => false,
    );
    Future.microtask(() {
      _redirectScheduled = false;
    });
  }
}
