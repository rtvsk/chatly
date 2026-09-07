import 'package:flutter/material.dart';

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
}
