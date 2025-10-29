class Insight {
  final String id;
  final String userId;
  final String content;
  final DateTime generatedAt;
  final String dataHash;
  final DateTime? expiresAt;

  Insight({
    required this.id,
    required this.userId,
    required this.content,
    required this.generatedAt,
    required this.dataHash,
    this.expiresAt,
  });

  factory Insight.fromJson(Map<String, dynamic> json) {
    return Insight(
      id: json['id'],
      userId: json['user_id'],
      content: json['content'],
      generatedAt: DateTime.parse(json['generated_at']),
      dataHash: json['data_hash'],
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
    );
  }
}