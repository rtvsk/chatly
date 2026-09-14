import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../constants.dart';
import '../models/chat.dart';
import '../navigation/app_navigation.dart';
import '../storage/token_storage.dart';
import 'auth_service.dart';

class TypingChangedEvent {
  const TypingChangedEvent({required this.userId, required this.isTyping});

  final String userId;
  final bool isTyping;
}

enum FriendshipChangeType {
  requestCreated('request_created'),
  requestAccepted('request_accepted'),
  requestRejected('request_rejected'),
  friendRemoved('friend_removed');

  const FriendshipChangeType(this.value);

  final String value;

  static FriendshipChangeType? fromValue(String value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

class FriendshipChangedEvent {
  const FriendshipChangedEvent({required this.type});

  final FriendshipChangeType type;
}

abstract interface class ChatRealtime {
  Stream<ChatMessage> get messages;

  /// Broadcasts validated typing-state changes received from other users.
  Stream<TypingChangedEvent> get typingChanges;

  /// Broadcasts validated friendship changes received from the server.
  Stream<FriendshipChangedEvent> get friendshipChanges;

  /// Emits after each successful Socket.IO connection, including reconnects.
  Stream<void> get connected;

  /// The most recently received immutable set of online user IDs.
  Set<String> get onlineUserIds;

  /// Broadcasts each change to the immutable set of online user IDs.
  Stream<Set<String>> get onlineUserIdsChanges;

  Future<void> connect();

  /// Requests a fresh presence snapshot when the socket is connected.
  void refreshPresence();

  /// Tells [recipientUserId] whether the current user is composing a message.
  void setTyping({required String recipientUserId, required bool isTyping});

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
  final StreamController<TypingChangedEvent> _typingChanges =
      StreamController<TypingChangedEvent>.broadcast();
  final StreamController<FriendshipChangedEvent> _friendshipChanges =
      StreamController<FriendshipChangedEvent>.broadcast();
  final StreamController<void> _connected = StreamController<void>.broadcast();
  final StreamController<Set<String>> _onlineUserIdsChanges =
      StreamController<Set<String>>.broadcast();

  io.Socket? _socket;
  Set<String> _onlineUserIds = const {};
  bool _explicitlyDisconnected = false;
  bool _refreshInProgress = false;
  bool _refreshAttempted = false;
  int _generation = 0;

  @override
  Stream<ChatMessage> get messages => _messages.stream;

  @override
  Stream<TypingChangedEvent> get typingChanges => _typingChanges.stream;

  @override
  Stream<FriendshipChangedEvent> get friendshipChanges =>
      _friendshipChanges.stream;

  @override
  Stream<void> get connected => _connected.stream;

  @override
  Set<String> get onlineUserIds => _onlineUserIds;

  @override
  Stream<Set<String>> get onlineUserIdsChanges => _onlineUserIdsChanges.stream;

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

    socket.onAny((event, data) {
      debugPrint('WS IN  $event: $data');
    });
    socket.onAnyOutgoing((String event, [dynamic data]) {
      debugPrint('WS OUT $event: $data');
    });
    socket.onConnect((_) {
      debugPrint('WS CONNECTED: ${socket.id}');
    });
    socket.onDisconnect((reason) {
      debugPrint('WS DISCONNECTED: $reason');
    });
    socket.onConnectError((error) {
      debugPrint('WS CONNECT ERROR: $error');
    });

    socket.onConnect((_) {
      if (!_isCurrent(generation, socket)) return;
      _refreshAttempted = false;
      _connected.add(null);
      refreshPresence();
    });
    socket.on('message.created', (payload) {
      if (!_isCurrent(generation, socket) || payload is! Map) return;
      try {
        _messages.add(ChatMessage.fromJson(Map<String, dynamic>.from(payload)));
      } catch (_) {
        // Malformed realtime payloads must not terminate the authenticated UI.
      }
    });
    socket.on('typing.changed', (payload) {
      if (!_isCurrent(generation, socket) || payload is! Map) return;

      final userId = payload['userId'];
      final isTyping = payload['isTyping'];
      if (userId is! String || isTyping is! bool) return;

      _typingChanges.add(
        TypingChangedEvent(userId: userId, isTyping: isTyping),
      );
    });
    socket.on('friendship.changed', (payload) {
      if (!_isCurrent(generation, socket) || payload is! Map) return;

      final value = payload['type'];
      if (value is! String) return;
      final type = FriendshipChangeType.fromValue(value);
      if (type == null) return;

      _friendshipChanges.add(FriendshipChangedEvent(type: type));
    });
    socket.on('presence.snapshot', (payload) {
      if (!_isCurrent(generation, socket) || payload is! Map) return;

      final onlineUserIds = payload['onlineUserIds'];
      if (onlineUserIds is! List || onlineUserIds.any((id) => id is! String)) {
        return;
      }

      _setOnlineUserIds(onlineUserIds.cast<String>());
    });
    socket.on('presence.changed', (payload) {
      if (!_isCurrent(generation, socket) || payload is! Map) return;

      final userId = payload['userId'];
      final isOnline = payload['isOnline'];
      if (userId is! String || isOnline is! bool) return;

      final updatedOnlineUserIds = Set<String>.from(_onlineUserIds);
      if (isOnline) {
        updatedOnlineUserIds.add(userId);
      } else {
        updatedOnlineUserIds.remove(userId);
      }
      _setOnlineUserIds(updatedOnlineUserIds);
    });
    socket.onDisconnect((_) {
      if (!_isCurrent(generation, socket)) return;
      _setOnlineUserIds(const {}, forceEmit: true);
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

  @override
  void refreshPresence() {
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    socket.emit('presence.get');
  }

  @override
  void setTyping({required String recipientUserId, required bool isTyping}) {
    final socket = _socket;
    if (socket == null || !socket.connected) return;

    socket.emit('typing.set', {
      'recipientUserId': recipientUserId,
      'isTyping': isTyping,
    });
  }

  void _setOnlineUserIds(Iterable<String> userIds, {bool forceEmit = false}) {
    final updatedOnlineUserIds = Set<String>.unmodifiable(userIds);
    if (!forceEmit &&
        _onlineUserIds.length == updatedOnlineUserIds.length &&
        _onlineUserIds.containsAll(updatedOnlineUserIds)) {
      return;
    }

    _onlineUserIds = updatedOnlineUserIds;
    _onlineUserIdsChanges.add(_onlineUserIds);
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
    _setOnlineUserIds(const {}, forceEmit: true);
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
