import 'dart:async';

import 'package:chatly/models/chat.dart';
import 'package:chatly/services/chat_realtime_service.dart';

class FakeChatRealtime implements ChatRealtime {
  late final StreamController<ChatMessage> _messagesController;
  late final StreamController<void> _connectedController;
  int messageSubscriptions = 0;
  int messageCancellations = 0;
  int connectedSubscriptions = 0;
  int connectedCancellations = 0;
  int connectCalls = 0;
  int disconnectCalls = 0;

  FakeChatRealtime() {
    _messagesController = StreamController<ChatMessage>.broadcast(
      onListen: () => messageSubscriptions++,
      onCancel: () => messageCancellations++,
    );
    _connectedController = StreamController<void>.broadcast(
      onListen: () => connectedSubscriptions++,
      onCancel: () => connectedCancellations++,
    );
  }

  @override
  Stream<ChatMessage> get messages => _messagesController.stream;

  @override
  Stream<void> get connected => _connectedController.stream;

  @override
  Future<void> connect() async {
    connectCalls++;
  }

  @override
  void disconnect() {
    disconnectCalls++;
  }

  void addMessage(ChatMessage message) => _messagesController.add(message);

  void signalConnected() => _connectedController.add(null);
}
