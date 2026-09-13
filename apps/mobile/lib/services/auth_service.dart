import 'dart:convert';

import 'package:chatly/constants.dart';
import 'package:http/http.dart' as http;

import '../storage/token_storage.dart';

sealed class AuthenticationResult {
  const AuthenticationResult();
}

class Authenticated extends AuthenticationResult {
  const Authenticated();
}

class VerificationRequired extends AuthenticationResult {
  const VerificationRequired({required this.email, this.delivery, this.login});

  final String email;
  final String? delivery;
  final String? login;
}

class AuthenticationFailed extends AuthenticationResult {
  const AuthenticationFailed();
}

sealed class SignupResult {
  const SignupResult();
}

class SignupVerificationRequired extends SignupResult {
  const SignupVerificationRequired({
    required this.email,
    required this.delivery,
    required this.login,
  });

  final String email;
  final String delivery;
  final String login;
}

class SignupFailed extends SignupResult {
  const SignupFailed();
}

class AuthService {
  AuthService({http.Client? client, AuthSessionStorage? storage})
    : _client = client ?? http.Client(),
      _storage = storage ?? TokenStorage.instance;

  final http.Client _client;
  final AuthSessionStorage _storage;

  Future<AuthenticationResult> refreshSession() async {
    final refreshToken = await _storage.getRefreshToken();

    if (refreshToken == null || refreshToken.isEmpty) {
      return const AuthenticationFailed();
    }

    try {
      final response = await _client.post(
        Uri.parse('${Constants.baseUrl}/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );

      if (_isVerificationRequired(response)) {
        return await _verificationResult(
          response,
          login: await _storage.getUserLogin(),
        );
      }

      if (!_isSuccess(response)) {
        await _storage.clearSession();
        return const AuthenticationFailed();
      }

      await _saveTokenResponse(response);
      return const Authenticated();
    } catch (_) {
      await _storage.clearSession();
      return const AuthenticationFailed();
    }
  }

  Future<SignupResult> signup({
    required String login,
    required String email,
    required String password,
    required String repeatPassword,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${Constants.baseUrl}/auth/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'login': login,
          'email': email.trim().toLowerCase(),
          'password': password,
          'repeatPassword': repeatPassword,
        }),
      );

      if (!_isSuccess(response)) return const SignupFailed();

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'verification_required') {
        return const SignupFailed();
      }

      final user = data['user'] as Map<String, dynamic>;
      final verificationEmail = user['email'] as String;
      final delivery = data['delivery'] as String;
      await _storage.clearSession();
      return SignupVerificationRequired(
        email: verificationEmail,
        delivery: delivery,
        login: user['login'] as String,
      );
    } catch (_) {
      return const SignupFailed();
    }
  }

  Future<AuthenticationResult> signin({
    required String login,
    required String password,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${Constants.baseUrl}/auth/signin'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'login': login, 'password': password}),
      );

      if (_isVerificationRequired(response)) {
        return await _verificationResult(response, login: login);
      }

      if (!_isSuccess(response)) return const AuthenticationFailed();

      await _saveTokenResponse(response);
      return const Authenticated();
    } catch (_) {
      return const AuthenticationFailed();
    }
  }

  Future<bool> resendVerification({required String email}) async {
    try {
      final response = await _client.post(
        Uri.parse('${Constants.baseUrl}/auth/resend-verification'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.trim().toLowerCase()}),
      );
      return response.statusCode == 202;
    } catch (_) {
      return false;
    }
  }

  bool _isSuccess(http.Response response) {
    return response.statusCode == 200 || response.statusCode == 201;
  }

  bool _isVerificationRequired(http.Response response) {
    if (response.statusCode != 403) return false;

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['code'] == 'EMAIL_NOT_VERIFIED' && data['email'] is String;
    } catch (_) {
      return false;
    }
  }

  Future<VerificationRequired> _verificationResult(
    http.Response response, {
    String? login,
  }) async {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await _storage.clearSession();
    return VerificationRequired(email: data['email'] as String, login: login);
  }

  Future<void> _saveTokenResponse(http.Response response) async {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final user = data['user'] as Map<String, dynamic>;
    await _storage.saveTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      userLogin: user['login'] as String,
    );
  }
}
