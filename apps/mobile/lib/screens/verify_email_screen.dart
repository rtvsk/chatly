import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'signin_screen.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    required this.email,
    this.delivery = 'sent',
    this.login,
    this.authService,
  });

  final String email;
  final String delivery;
  final String? login;
  final AuthService? authService;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  static const _resendCooldown = Duration(seconds: 60);

  late final AuthService _authService = widget.authService ?? AuthService();
  Timer? _cooldownTimer;
  int _secondsRemaining = 0;
  bool _isSending = false;
  String? _status;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    setState(() {
      _isSending = true;
      _status = null;
    });

    final wasAccepted = await _authService.resendVerification(
      email: widget.email,
    );
    if (!mounted) return;

    setState(() {
      _isSending = false;
      _status = wasAccepted
          ? 'Verification email sent.'
          : 'Unable to resend verification email. Please try again.';
    });

    if (wasAccepted) _startCooldown();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsRemaining = _resendCooldown.inSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _secondsRemaining <= 1) {
        timer.cancel();
        if (mounted) setState(() => _secondsRemaining = 0);
        return;
      }
      setState(() => _secondsRemaining--);
    });
  }

  @override
  Widget build(BuildContext context) {
    final deliveryText = widget.delivery == 'pending'
        ? 'We could not send the verification email yet. Please resend it.'
        : 'A verification email has been sent.';
    final resendLabel = _secondsRemaining > 0
        ? 'Resend in $_secondsRemaining s'
        : _isSending
        ? 'Resending...'
        : 'Resend verification email';

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Please Verify Your Email ${widget.email}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(deliveryText, textAlign: TextAlign.center),
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(_status!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('resend-verification-button'),
                onPressed: _isSending || _secondsRemaining > 0 ? null : _resend,
                child: Text(resendLabel),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => SigninScreen(initialLogin: widget.login),
                    ),
                    (_) => false,
                  );
                },
                child: const Text('Back to Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
