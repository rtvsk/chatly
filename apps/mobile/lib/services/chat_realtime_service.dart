import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../constants.dart';
import '../models/chat.dart';
import '../navigation/app_navigation.dart';
import '../storage/token_storage.dart';
import 'auth_service.dart';

abstract interface class ChatRealtime {
  Stream<ChatMessage> get messages;

  /// Emits after each successful Socket.IO connection, including reconnects.
  Stream<void> get connected;

  Future<void> connect();

  void disconnect();
}

class ChatRealtimeService implements ChatRealtime {
  ChatRealtimeService({
    AuthService? authService,
    String? Function()? accessToken,
    io.Socket Function(String uri, Map<String, dynamic> options)? socketFactory,
  }) : _authService = authService ?? AuthService(),
       _accessToken = accessToken ?? (() => TokenStorage.instance.accessToken),
       _socketFactory = socketFactory ?? io.io;

  static final ChatRealtimeService instance = ChatRealtimeService();

  final AuthService _authService;
  final String? Function() _accessToken;
  final io.Socket Function(String uri, Map<String, dynamic> options)
  _socketFactory;
  final StreamController<ChatMessage> _messages =
      StreamController<ChatMessage>.broadcast();
  final StreamController<void> _connected = StreamController<void>.broadcast();

  io.Socket? _socket;
  bool _explicitlyDisconnected = false;
  bool _refreshInProgress = false;
  bool _refreshAttempted = false;
  int _generation = 0;

  @override
  Stream<ChatMessage> get messages => _messages.stream;

  @override
  Stream<void> get connected => _connected.stream;

  @override
  Future<void> connect() async {
    final accessToken = _accessToken();
    if (accessToken == null || accessToken.isEmpty) {
      disconnect();
      return;
    }

    _explicitlyDisconnected = false;
    _openSocket(accessToken);
  }

  void _openSocket(String accessToken) {
    _closeSocket();
    final generation = ++_generation;
    final socket = _socketFactory(
      '${Constants.baseUrl}/chats',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': accessToken})
          .enableForceNew()
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      if (!_isCurrent(generation, socket)) return;
      _refreshAttempted = false;
      _connected.add(null);
    });
    socket.on('message.created', (payload) {
      if (!_isCurrent(generation, socket) || payload is! Map) return;
      try {
        _messages.add(ChatMessage.fromJson(Map<String, dynamic>.from(payload)));
      } catch (_) {
        // Malformed realtime payloads must not terminate the authenticated UI.
      }
    });
    socket.onConnectError(
      (error) => unawaited(_handleConnectError(error, generation, socket)),
    );
    socket.connect();
  }

  bool _isCurrent(int generation, io.Socket socket) {
    return !_explicitlyDisconnected &&
        generation == _generation &&
        identical(_socket, socket);
  }

  Future<void> _handleConnectError(
    dynamic error,
    int generation,
    io.Socket socket,
  ) async {
    if (!_isCurrent(generation, socket) ||
        !_isAuthenticationError(error) ||
        _refreshInProgress ||
        _refreshAttempted) {
      return;
    }

    _refreshInProgress = true;
    _refreshAttempted = true;
    try {
      final result = await _authService.refreshSession();
      if (!_isCurrent(generation, socket)) return;

      if (result is Authenticated) {
        final refreshedToken = _accessToken();
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          _openSocket(refreshedToken);
          return;
        }
      }

      disconnect();
      _showAuthenticationFailure(result);
    } finally {
      _refreshInProgress = false;
    }
  }

  bool _isAuthenticationError(dynamic error) {
    final message = error is Map ? error['message'] : error;
    final value = '$message'.toLowerCase();
    return value.contains('unauthor') ||
        value.contains('jwt') ||
        value.contains('token') ||
        value.contains('authentication');
  }

  void _showAuthenticationFailure(AuthenticationResult result) {
    if (result is VerificationRequired) {
      AppNavigation.showVerification(email: result.email, login: result.login);
    } else {
      AppNavigation.showSignup();
    }
  }

  @override
  void disconnect() {
    _explicitlyDisconnected = true;
    ++_generation;
    _closeSocket();
  }

  void _closeSocket() {
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    socket.clearListeners();
    socket.disconnect();
    socket.dispose();
  }
}
