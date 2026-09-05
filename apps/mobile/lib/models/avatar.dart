class Avatar {
  const Avatar({
    required this.id,
    required this.originalName,
    required this.mimeType,
    required this.size,
    required this.isSelected,
    required this.createdAt,
    required this.url,
  });

  final String id;
  final String originalName;
  final String mimeType;
  final int size;
  final bool isSelected;
  final DateTime createdAt;
  final String url;

  factory Avatar.fromJson(Map<String, dynamic> json) {
    return Avatar(
      id: json['id'] as String,
      originalName: json['originalName'] as String,
      mimeType: json['mimeType'] as String,
      size: json['size'] as int,
      isSelected: json['isSelected'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      url: json['url'] as String,
    );
  }
}
