import 'package:frontend/utils/date_parsing.dart';

/// The server refused to translate an insight (the hidden monthly AI limit, or
/// a used-up translation allowance) although the plan includes translation.
/// Same fields as a plan limit error; the English insight is still returned.
class TranslationUnavailable {
  /// `plan_cost_cap`, `plan_limit_reached` (or `plan_feature_locked`).
  final String code;

  /// Already in the user's language, so it may be shown as is.
  final String message;
  final DateTime? resetsAt;
  final bool upgradeAvailable;

  const TranslationUnavailable({
    required this.code,
    this.message = '',
    this.resetsAt,
    this.upgradeAvailable = false,
  });

  /// Null unless [json] is an object (the server sends null normally).
  static TranslationUnavailable? tryParse(dynamic json) {
    if (json is! Map) return null;
    final code = json['code'];
    if (code is! String || code.isEmpty) return null;
    return TranslationUnavailable(
      code: code,
      message: json['message'] is String ? json['message'] as String : '',
      resetsAt: parseInstantOrNull(json['resets_at']),
      upgradeAvailable: json['upgrade_available'] == true,
    );
  }
}

class Insight {
  final String id;
  final String userId;
  final String content;
  final String? contentMm; // Myanmar translation
  final DateTime generatedAt;
  final DateTime? expiresAt;

  /// Myanmar was asked for but the plan has no translation: [content] is the
  /// English text and [contentMm] is null.
  final bool translationLocked;

  /// Myanmar was asked for and the plan has translation, but the server
  /// refused to translate it now (a limit): [content] is the English text,
  /// [contentMm] is null and this says why. Null normally.
  final TranslationUnavailable? translationUnavailable;

  Insight({
    required this.id,
    required this.userId,
    required this.content,
    this.contentMm,
    required this.generatedAt,
    this.expiresAt,
    this.translationLocked = false,
    this.translationUnavailable,
  });

  factory Insight.fromJson(Map<String, dynamic> json) {
    return Insight(
      id: json['id'],
      userId: json['user_id'],
      content: json['content'],
      contentMm: json['content_mm'],
      generatedAt: parseInstantOrNull(json['generated_at']) ?? DateTime.now(),
      expiresAt: parseInstantOrNull(json['expires_at']),
      translationLocked: json['translation_locked'] == true,
      translationUnavailable:
          TranslationUnavailable.tryParse(json['translation_unavailable']),
    );
  }
}
