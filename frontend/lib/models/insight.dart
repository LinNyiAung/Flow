class Insight {
  final String id;
  final String userId;
  final String content;
  final String? contentMm;  // NEW: Myanmar translation
  final DateTime generatedAt;
  final DateTime? expiresAt;

  Insight({
    required this.id,
    required this.userId,
    required this.content,
    this.contentMm,  // NEW
    required this.generatedAt,
    this.expiresAt,
  });

  factory Insight.fromJson(Map<String, dynamic> json) {
    DateTime parseDateTime(String dateStr) {
      try {
        if (dateStr.endsWith('Z')) {
          return DateTime.parse(dateStr).toLocal();
        }
        if (dateStr.contains('+') || dateStr.contains('T') && dateStr.split('T')[1].contains('-')) {
          return DateTime.parse(dateStr).toLocal();
        }
        return DateTime.parse(dateStr + 'Z').toLocal();
      } catch (e) {
        print('Error parsing date: $dateStr - $e');
        return DateTime.now().toLocal();
      }
    }

    return Insight(
      id: json['id'],
      userId: json['user_id'],
      content: json['content'],
      contentMm: json['content_mm'],  // NEW
      generatedAt: parseDateTime(json['generated_at']),
      expiresAt: json['expires_at'] != null
          ? parseDateTime(json['expires_at'])
          : null,
    );
  }
}