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
    // Parse date safely - handle both with and without timezone
    DateTime parseDateTime(String dateStr) {
      try {
        // If it already ends with 'Z', parse as-is
        if (dateStr.endsWith('Z')) {
          return DateTime.parse(dateStr).toLocal();
        }
        // If it contains timezone info (+ or -), parse as-is
        if (dateStr.contains('+') || dateStr.contains('T') && dateStr.split('T')[1].contains('-')) {
          return DateTime.parse(dateStr).toLocal();
        }
        // Otherwise, add 'Z' to indicate UTC
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
      generatedAt: parseDateTime(json['generated_at']),
      dataHash: json['data_hash'],
      expiresAt: json['expires_at'] != null
          ? parseDateTime(json['expires_at'])
          : null,
    );
  }
}