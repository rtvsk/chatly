import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'package:flutter_driver/driver_extension.dart';

import 'navigation/app_navigation.dart';
import 'screens/signup_screen.dart';

void main() {
  if (const bool.fromEnvironment('ENABLE_FLUTTER_DRIVER')) {
    enableFlutterDriverExtension();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppNavigation.navigatorKey,
      routes: {AppNavigation.signupRoute: (_) => const SignupScreen()},
      home: const SplashScreen(),
    );
  }
}
