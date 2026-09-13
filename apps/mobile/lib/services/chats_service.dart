import 'dart:convert';

import '../models/chat.dart';
import 'api_service.dart';

class ChatsService {
  const ChatsService();

  Future<List<ChatSummary>> getChats() async {
    final response = await ApiService.instance.get('/chats');
    _requireSuccess(response.statusCode);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final chats = data['chats'] as List<dynamic>;
    return chats
        .map((item) => ChatSummary.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ChatSummary?> getDirectChat(String userId) async {
    final response = await ApiService.instance.get('/chats/direct/$userId');
    _requireSuccess(response.statusCode);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final chat = data['chat'];
    return chat == null
        ? null
        : ChatSummary.fromJson(chat as Map<String, dynamic>);
  }

  Future<ChatSummary> createDirectChat(String userId) async {
    final response = await ApiService.instance.post('/chats/direct/$userId');
    _requireSuccess(response.statusCode);
    return ChatSummary.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<ChatMessage>> getMessages(String chatId, {String? after}) async {
    final query = after == null
        ? ''
        : '?after=${Uri.encodeQueryComponent(after)}';
    final response = await ApiService.instance.get(
      '/chats/$chatId/messages$query',
    );
    _requireSuccess(response.statusCode);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final messages = data['messages'] as List<dynamic>;
    return messages
        .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ChatMessage> sendMessage(String chatId, String text) async {
    final response = await ApiService.instance.post(
      '/chats/$chatId/messages',
      body: {'text': text},
    );
    _requireSuccess(response.statusCode);
    return ChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  void _requireSuccess(int statusCode) {
    if (statusCode < 200 || statusCode >= 300) {
      throw Exception('Chat request failed ($statusCode)');
    }
  }
}
