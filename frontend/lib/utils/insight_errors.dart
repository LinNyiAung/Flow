import 'package:frontend/services/localization_service.dart';

/// Matches a rate-limit hint inside a raw error message, e.g. the legacy
/// backend's `500 "Failed to generate insights: 429 RESOURCE_EXHAUSTED"`.
final RegExp _rateLimitHint = RegExp(
  r'(?<!\d)429(?!\d)|rate[\s_-]?limit|resource[\s_]?exhausted|too many requests',
  caseSensitive: false,
);

/// True when [rawMessage] says the AI provider rate-limited the request.
bool insightMessageLooksRateLimited(String? rawMessage) =>
    rawMessage != null && _rateLimitHint.hasMatch(rawMessage);

/// User-facing message for a failed insights request, chosen from the HTTP
/// status code carried by the provider ([InsightProvider.errorStatusCode] /
/// [InsightProvider.actionErrorStatusCode]).
///
/// * 429 → rate limited
/// * a legacy 500 whose message mentions 429 / rate limit → rate limited
///   (the message is checked before the status-code mapping)
/// * 502 / 503 → temporarily unavailable (AI provider down / overloaded)
/// * other 5xx → server error
String insightErrorMessage(
  int? statusCode,
  AppLocalizations localizations, {
  String? rawMessage,
}) {
  if (statusCode == 429) return localizations.insightsRateLimited;
  if (insightMessageLooksRateLimited(rawMessage)) {
    return localizations.insightsRateLimited;
  }
  if (statusCode == 502 || statusCode == 503) {
    return localizations.insightsTemporarilyUnavailable;
  }
  if (statusCode != null && statusCode >= 500) {
    return localizations.insightsServerError;
  }
  return localizations.insightsGenericError;
}
