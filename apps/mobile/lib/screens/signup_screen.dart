import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import 'chats_screen.dart';
import 'signin_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repeatPasswordController = TextEditingController();

  final _authService = AuthService();

  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    _repeatPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    final login = _loginController.text.trim();
    final password = _passwordController.text;
    final repeatPassword = _repeatPasswordController.text;

    if (login.isEmpty || password.isEmpty || repeatPassword.isEmpty) {
      setState(() {
        _errorText = 'Please fill in all fields';
      });
      return;
    }

    if (password != repeatPassword) {
      setState(() {
        _errorText = 'Passwords do not match';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final success = await _authService.signup(
      login: login,
      password: password,
      repeatPassword: repeatPassword,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (!success) {
      setState(() {
        _errorText = 'Failed to create account';
      });
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const ChatsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _loginController,
              decoration: const InputDecoration(
                labelText: 'Login',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _repeatPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Repeat password',
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorText!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : _signup,
                child: Text(_isLoading ? 'Signing up...' : 'Sign up'),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SigninScreen(),
                        ),
                      );
                    },
              child: const Text('Already registered? Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}