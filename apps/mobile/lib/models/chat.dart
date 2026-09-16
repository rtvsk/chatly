import 'contact.dart';

class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.type,
    required this.peer,
    required this.createdAt,
    required this.updatedAt,
    required this.unreadCount,
    this.lastMessage,
  });

  final String id;
  final String type;
  final Contact peer;
  final ChatMessage? lastMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int unreadCount;

  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    return ChatSummary(
      id: json['id'] as String,
      type: json['type'] as String,
      peer: Contact.fromJson(json['peer'] as Map<String, dynamic>),
      lastMessage: json['lastMessage'] == null
          ? null
          : ChatMessage.fromJson(json['lastMessage'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      unreadCount: json['unreadCount'] as int,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    required this.readByPeer,
  });

  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool readByPeer;

  ChatMessage copyWith({bool? readByPeer}) {
    return ChatMessage(
      id: id,
      chatId: chatId,
      senderId: senderId,
      text: text,
      createdAt: createdAt,
      updatedAt: updatedAt,
      readByPeer: readByPeer ?? this.readByPeer,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      chatId: json['chatId'] as String,
      senderId: json['senderId'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      readByPeer: json['readByPeer'] as bool,
    );
  }
}
