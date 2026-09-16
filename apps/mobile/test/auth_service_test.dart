import 'dart:async';
import 'dart:convert';

import 'package:chatly/services/auth_service.dart';
import 'package:chatly/storage/token_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemorySessionStorage implements AuthSessionStorage {
  String? refreshToken;
  String? userLogin;
  int clearCount = 0;
  String? savedAccessToken;

  @override
  Future<void> clearSession() async {
    clearCount++;
    refreshToken = null;
    userLogin = null;
  }

  @override
  Future<String?> getRefreshToken() async => refreshToken;

  @override
  Future<String?> getUserLogin() async => userLogin;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String userLogin,
  }) async {
    savedAccessToken = accessToken;
    this.refreshToken = refreshToken;
    this.userLogin = userLogin;
  }
}

void main() {
  group('AuthService', () {
    test('signup sends normalized email and requires verification', () async {
      final storage = MemorySessionStorage();
      late Map<String, dynamic> requestBody;
      final service = AuthService(
        storage: storage,
        client: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'status': 'verification_required',
              'user': {
                'id': 'user-1',
                'login': 'alice',
                'email': 'alice@example.com',
                'isVerified': false,
              },
              'delivery': 'pending',
            }),
            201,
          );
        }),
      );

      final result = await service.signup(
        login: 'alice',
        email: ' Alice@Example.COM ',
        password: 'password',
        repeatPassword: 'password',
      );

      expect(requestBody['email'], 'alice@example.com');
      expect(result, isA<SignupVerificationRequired>());
      final verification = result as SignupVerificationRequired;
      expect(verification.email, 'alice@example.com');
      expect(verification.delivery, 'pending');
      expect(storage.savedAccessToken, isNull);
      expect(storage.clearCount, 1);
    });

    test('signin maps EMAIL_NOT_VERIFIED to a typed result', () async {
      final storage = MemorySessionStorage();
      final service = AuthService(
        storage: storage,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'code': 'EMAIL_NOT_VERIFIED',
              'message': 'Verify your email',
              'email': 'alice@example.com',
            }),
            403,
          ),
        ),
      );

      final result = await service.signin(login: 'alice', password: 'password');

      expect(result, isA<VerificationRequired>());
      final verification = result as VerificationRequired;
      expect(verification.email, 'alice@example.com');
      expect(verification.login, 'alice');
      expect(storage.savedAccessToken, isNull);
      expect(storage.clearCount, 1);
    });

    test('verified signin saves tokens and authenticates', () async {
      final storage = MemorySessionStorage();
      final service = AuthService(
        storage: storage,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'accessToken': 'access',
              'refreshToken': 'refresh',
              'user': {'login': 'alice', 'email': 'alice@example.com'},
            }),
            201,
          ),
        ),
      );

      final result = await service.signin(login: 'alice', password: 'password');

      expect(result, isA<Authenticated>());
      expect(storage.savedAccessToken, 'access');
      expect(storage.refreshToken, 'refresh');
      expect(storage.userLogin, 'alice');
    });

    test('refresh clears session and exposes unverified email', () async {
      final storage = MemorySessionStorage()
        ..refreshToken = 'old-refresh'
        ..userLogin = 'alice';
      final service = AuthService(
        storage: storage,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'code': 'EMAIL_NOT_VERIFIED',
              'message': 'Verify your email',
              'email': 'alice@example.com',
            }),
            403,
          ),
        ),
      );

      final result = await service.refreshSession();

      expect(result, isA<VerificationRequired>());
      final verification = result as VerificationRequired;
      expect(verification.login, 'alice');
      expect(storage.refreshToken, isNull);
      expect(storage.clearCount, 1);
    });

    test('coalesces concurrent refreshes and allows a later refresh', () async {
      final storage = MemorySessionStorage()..refreshToken = 'old-refresh';
      final responseCompleter = Completer<void>();
      final requestStarted = Completer<void>();
      var requestCount = 0;
      final client = MockClient((_) async {
        requestCount++;
        if (!requestStarted.isCompleted) requestStarted.complete();
        await responseCompleter.future;
        return http.Response(
          jsonEncode({
            'accessToken': 'access',
            'refreshToken': 'refresh',
            'user': {'login': 'alice', 'email': 'alice@example.com'},
          }),
          201,
        );
      });
      final firstService = AuthService(storage: storage, client: client);
      final secondService = AuthService(storage: storage, client: client);

      final firstRefresh = firstService.refreshSession();
      await requestStarted.future;
      final secondRefresh = secondService.refreshSession();
      responseCompleter.complete();

      final results = await Future.wait([firstRefresh, secondRefresh]);

      expect(results, everyElement(isA<Authenticated>()));
      expect(requestCount, 1);

      expect(await firstService.refreshSession(), isA<Authenticated>());
      expect(requestCount, 2);
    });

    test('resend accepts the generic 202 response', () async {
      final service = AuthService(
        storage: MemorySessionStorage(),
        client: MockClient((request) async {
          expect(request.url.path, '/auth/resend-verification');
          expect(request.body, contains('alice@example.com'));
          return http.Response(jsonEncode({'status': 'accepted'}), 202);
        }),
      );

      expect(
        await service.resendVerification(email: 'Alice@Example.COM'),
        isTrue,
      );
    });
  });
}
