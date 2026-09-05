import 'dart:convert';

import 'package:chatly/constants.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'auth_service.dart';
import '../storage/token_storage.dart';

class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  final AuthService _authService = AuthService();

  Future<http.Response> get(String path) {
    return _sendWithRefresh(
      () =>
          http.get(Uri.parse('${Constants.baseUrl}$path'), headers: _headers()),
    );
  }

  Future<http.Response> post(String path, {Object? body}) {
    return _sendWithRefresh(
      () => http.post(
        Uri.parse('${Constants.baseUrl}$path'),
        headers: _headers(),
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Future<http.Response> patch(String path) {
    return _sendWithRefresh(
      () => http.patch(
        Uri.parse('${Constants.baseUrl}$path'),
        headers: _headers(),
      ),
    );
  }

  Future<http.Response> delete(String path) {
    return _sendWithRefresh(
      () => http.delete(
        Uri.parse('${Constants.baseUrl}$path'),
        headers: _headers(),
      ),
    );
  }

  Future<http.Response> multipartPost(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    String? mimeType,
  }) {
    return _sendWithRefresh(() async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${Constants.baseUrl}$path'),
      );
      request.headers.addAll(authorizationHeaders);
      request.files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          bytes,
          filename: filename,
          contentType: MediaType.parse(mimeType ?? 'application/octet-stream'),
        ),
      );

      return http.Response.fromStream(await request.send());
    });
  }

  Map<String, String> get authorizationHeaders {
    final accessToken = TokenStorage.instance.accessToken;

    return {
      if (accessToken != null && accessToken.isNotEmpty)
        'Authorization': 'Bearer $accessToken',
    };
  }

  Map<String, String> _headers() {
    return {'Content-Type': 'application/json', ...authorizationHeaders};
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
