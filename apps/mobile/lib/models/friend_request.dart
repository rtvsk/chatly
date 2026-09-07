import 'contact.dart';

class FriendRequest {
  const FriendRequest({
    required this.friendshipId,
    required this.user,
    required this.createdAt,
  });

  final String friendshipId;
  final Contact user;
  final DateTime createdAt;

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      friendshipId: json['friendshipId'] as String,
      user: Contact.fromJson(json['user'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

enum FriendshipState {
  none,
  friends,
  outgoingPending,
  incomingPending;

  static FriendshipState fromJson(String value) {
    return switch (value) {
      'friends' => friends,
      'outgoing_pending' => outgoingPending,
      'incoming_pending' => incomingPending,
      _ => none,
    };
  }
}
