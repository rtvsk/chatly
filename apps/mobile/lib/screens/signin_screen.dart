import 'package:chatly/screens/chats_screen.dart';

import '../services/auth_service.dart';
import 'package:flutter/material.dart';
import 'verify_email_screen.dart';

class SigninScreen extends StatefulWidget {
  const SigninScreen({super.key, this.initialLogin, this.authService});

  final String? initialLogin;
  final AuthService? authService;

  @override
  State<SigninScreen> createState() => _SigninScreenState();
}

class _SigninScreenState extends State<SigninScreen> {
  late final _loginController = TextEditingController(
    text: widget.initialLogin,
  );
  final _passwordController = TextEditingController();

  late final AuthService _authService = widget.authService ?? AuthService();

  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signin() async {
    final login = _loginController.text.trim();
    final password = _passwordController.text;

    if (login.isEmpty || password.isEmpty) {
      setState(() {
        _errorText = 'Please fill in all fields';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final result = await _authService.signin(login: login, password: password);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result is AuthenticationFailed) {
      setState(() {
        _errorText = 'Failed to sign in';
      });
      return;
    }

    if (result is VerificationRequired) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VerifyEmailScreen(
            email: result.email,
            delivery: result.delivery ?? 'sent',
            login: result.login,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ChatsScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _loginController,
              decoration: InputDecoration(
                labelText: 'Login',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 16),
              Text(_errorText!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : _signin,
                child: Text(_isLoading ? 'Signing in...' : 'Sign in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
