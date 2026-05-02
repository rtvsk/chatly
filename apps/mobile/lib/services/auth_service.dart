import 'dart:convert';

import 'package:chatly/constants.dart';
import 'package:http/http.dart' as http;

import '../storage/token_storage.dart';

class AuthService {
  // static const String _baseUrl = 'http://localhost:3000';

  Future<bool> refreshSession() async {
    final refreshToken = await TokenStorage.instance.getRefreshToken();

    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('${Constants.baseUrl}/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'refreshToken': refreshToken,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        await TokenStorage.instance.clearSession();
        return false;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      await TokenStorage.instance.saveTokens(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
        userLogin: data['user']['login'] as String,
      );

      return true;
    } catch (_) {
      await TokenStorage.instance.clearSession();
      return false;
    }
  }

  Future<bool> signup({
    required String login,
    required String password,
    required String repeatPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${Constants.baseUrl}/auth/signup'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'login': login,
          'password': password,
          'repeatPassword': repeatPassword,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        return false;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      await TokenStorage.instance.saveTokens(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
        userLogin: data['user']['login'] as String,
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> signin({
    required String login,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${Constants.baseUrl}/auth/signin'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'login': login,
          'password': password,
        }),
      );
  
      if (response.statusCode != 200 && response.statusCode != 201) {
        return false;
      }
  
      final data = jsonDecode(response.body) as Map<String, dynamic>;
  
      await TokenStorage.instance.saveTokens(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
        userLogin: data['user']['login'] as String,
      );
  
      return true;
    } catch (_) {
      return false;
    }
  }
}