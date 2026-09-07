class Contact {
  const Contact({required this.id, required this.login, this.avatarUrl});

  final String id;
  final String login;
  final String? avatarUrl;

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] as String,
      login: json['login'] as String,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}
