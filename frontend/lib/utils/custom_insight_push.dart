/// The two push types of a custom insight (`type` in the push data, and the
/// stored notification's type). The report's id is the push's `subject_id`.
const String customInsightReadyType = 'custom_insight_ready';
const String customInsightFailedType = 'custom_insight_failed';

bool isCustomInsightPushType(Object? type) =>
    type == customInsightReadyType || type == customInsightFailedType;

/// The payload of the local notification shown for a custom insight push:
/// `custom_insight_ready|<report id>` (the id part is empty when there is none).
/// Null for any other push type.
String? customInsightPayload(Object? type, Object? subjectId) {
  if (!isCustomInsightPushType(type)) return null;
  return '$type|${subjectId is String ? subjectId : ''}';
}

/// Reads a [customInsightPayload] back into the full push type and the report
/// id (null when empty). Null for a payload that is not a custom insight's
/// (for example a plain notification id).
({String type, String? subjectId})? parseCustomInsightPayload(String? payload) {
  if (payload == null) return null;
  final cut = payload.indexOf('|');
  final type = cut < 0 ? payload : payload.substring(0, cut);
  if (!isCustomInsightPushType(type)) return null;
  final id = cut < 0 ? '' : payload.substring(cut + 1);
  return (type: type, subjectId: id.isEmpty ? null : id);
}
