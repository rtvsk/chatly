import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  TokenStorage._();

  static final TokenStorage instance = TokenStorage._();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _refreshTokenKey = 'refresh_token';
  static const String _userLoginKey = 'user_login';

  String? _accessToken;

  String? get accessToken => _accessToken;

  bool get hasAccessToken => _accessToken != null && _accessToken!.isNotEmpty;

  void saveAccessToken(String accessToken) {
    _accessToken = accessToken;
  }

  Future<void> saveRefreshToken(String refreshToken) async {
    await _secureStorage.write(
      key: _refreshTokenKey,
      value: refreshToken,
    );
  }

  Future<String?> getRefreshToken() {
    return _secureStorage.read(key: _refreshTokenKey);
  }

  Future<bool> hasRefreshToken() async {
    final refreshToken = await getRefreshToken();
    return refreshToken != null && refreshToken.isNotEmpty;
  }

  Future<void> saveUserLogin(String login) async {
    await _secureStorage.write(
      key: _userLoginKey,
      value: login,
    );

  }

  Future<String?> getUserLogin() {
    return _secureStorage.read(key: _userLoginKey);
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String userLogin,
  }) async {
    saveAccessToken(accessToken);

    await Future.wait([
      saveRefreshToken(refreshToken),
      saveUserLogin(userLogin)
    ]);
  }

  Future<void> clearSession() async {
    _accessToken = null;

    await Future.wait([
      _secureStorage.delete(key: _refreshTokenKey),
      _secureStorage.delete(key: _userLoginKey)
    ]);
  }
}