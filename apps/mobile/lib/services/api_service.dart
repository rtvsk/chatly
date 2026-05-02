import 'dart:convert';

import 'package:chatly/constants.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import '../storage/token_storage.dart';

class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  final AuthService _authService = AuthService();

  Future<http.Response> get(String path) {
    return _sendWithRefresh(
      () => http.get(
        Uri.parse('${Constants.baseUrl}$path'),
        headers: _headers(),
      ),
    );
  }

  Future<http.Response> post(
    String path, {
    Object? body,
  }) {
    return _sendWithRefresh(
      () => http.post(
        Uri.parse('${Constants.baseUrl}$path'),
        headers: _headers(),
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Map<String, String> _headers() {
    final accessToken = TokenStorage.instance.accessToken;

    return {
      'Content-Type': 'application/json',
      if (accessToken != null && accessToken.isNotEmpty)
        'Authorization': 'Bearer $accessToken',
    };
  }

  Future<http.Response> _sendWithRefresh(
    Future<http.Response> Function() request,
  ) async {
    final response = await request();

    if (response.statusCode != 401) {
      return response;
    }

    final refreshed = await _authService.refreshSession();

    if (!refreshed) {
      return response;
    }

    // Повторяем исходный запрос один раз уже с новым accessToken
    return request();
  }
}