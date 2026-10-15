import 'package:frontend/utils/date_parsing.dart';

class Insight {
  final String id;
  final String userId;
  final String content;
  final String? contentMm; // Myanmar translation
  final DateTime generatedAt;
  final DateTime? expiresAt;

  Insight({
    required this.id,
    required this.userId,
    required this.content,
    this.contentMm,
    required this.generatedAt,
    this.expiresAt,
  });

  factory Insight.fromJson(Map<String, dynamic> json) {
    return Insight(
      id: json['id'],
      userId: json['user_id'],
      content: json['content'],
      contentMm: json['content_mm'],
      generatedAt: parseInstantOrNull(json['generated_at']) ?? DateTime.now(),
      expiresAt: parseInstantOrNull(json['expires_at']),
    );
  }
}
