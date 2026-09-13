import 'dart:async';

import 'package:chatly/models/chat.dart';
import 'package:chatly/services/chat_realtime_service.dart';

class FakeChatRealtime implements ChatRealtime {
  late final StreamController<ChatMessage> _messagesController;
  late final StreamController<void> _connectedController;
  late final StreamController<Set<String>> _onlineUserIdsChangesController;
  int messageSubscriptions = 0;
  int messageCancellations = 0;
  int connectedSubscriptions = 0;
  int connectedCancellations = 0;
  int onlineUserIdsSubscriptions = 0;
  int onlineUserIdsCancellations = 0;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int refreshPresenceCalls = 0;
  Set<String> _onlineUserIds;

  FakeChatRealtime({Iterable<String> onlineUserIds = const []})
    : _onlineUserIds = Set<String>.unmodifiable(onlineUserIds) {
    _messagesController = StreamController<ChatMessage>.broadcast(
      onListen: () => messageSubscriptions++,
      onCancel: () => messageCancellations++,
    );
    _connectedController = StreamController<void>.broadcast(
      onListen: () => connectedSubscriptions++,
      onCancel: () => connectedCancellations++,
    );
    _onlineUserIdsChangesController = StreamController<Set<String>>.broadcast(
      onListen: () => onlineUserIdsSubscriptions++,
      onCancel: () => onlineUserIdsCancellations++,
    );
  }

  @override
  Stream<ChatMessage> get messages => _messagesController.stream;

  @override
  Stream<void> get connected => _connectedController.stream;

  @override
  Set<String> get onlineUserIds => _onlineUserIds;

  @override
  Stream<Set<String>> get onlineUserIdsChanges =>
      _onlineUserIdsChangesController.stream;

  @override
  Future<void> connect() async {
    connectCalls++;
  }

  @override
  void refreshPresence() {
    refreshPresenceCalls++;
  }

  @override
  void disconnect() {
    disconnectCalls++;
  }

  void addMessage(ChatMessage message) => _messagesController.add(message);

  void signalConnected() => _connectedController.add(null);

  void applyPresenceSnapshot(Iterable<String> onlineUserIds) {
    _onlineUserIds = Set<String>.unmodifiable(onlineUserIds);
    _onlineUserIdsChangesController.add(_onlineUserIds);
  }

  void applyPresenceChanged({required String userId, required bool isOnline}) {
    final updatedOnlineUserIds = Set<String>.from(_onlineUserIds);
    if (isOnline) {
      updatedOnlineUserIds.add(userId);
    } else {
      updatedOnlineUserIds.remove(userId);
    }
    applyPresenceSnapshot(updatedOnlineUserIds);
  }
}
