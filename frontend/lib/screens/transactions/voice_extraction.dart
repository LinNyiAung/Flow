import 'package:frontend/models/voice_image_models.dart';
import 'package:frontend/services/api_service.dart';

/// Reads transactions out of a transcript ([ApiService.extractMultipleTransactionsFromText]).
typedef TextExtractor = Future<MultipleExtractedTransactions> Function(
  String text, {
  String? voiceToken,
});

/// One transcribed recording waiting to be read into transactions.
///
/// The server has already counted the voice entry when it transcribed, and the
/// [voiceToken] it returned makes the text extraction of that exact transcript
/// free. So when the extraction fails, running [extract] again with the same
/// transcript and token costs no second entry and needs no new recording.
class VoiceExtraction {
  final String transcript;
  final String? voiceToken;
  final TextExtractor _extractor;

  VoiceExtraction(
    TranscriptionResult transcription, {
    TextExtractor? extractor,
  })  : transcript = transcription.transcription,
        voiceToken = transcription.voiceToken,
        _extractor = extractor ?? ApiService.extractMultipleTransactionsFromText;

  /// Extracts with the original transcript and token, every time.
  Future<MultipleExtractedTransactions> extract() =>
      _extractor(transcript, voiceToken: voiceToken);

  /// When the voice token stops being valid: its first part is the expiry as
  /// unix seconds (`<expiry>.<signature>`). Null when there is no token or it
  /// does not look like one.
  static DateTime? tokenExpiry(String? token) {
    if (token == null) return null;
    final match = RegExp(r'^(\d+)\.(.+)$').firstMatch(token);
    final seconds = int.tryParse(match?.group(1) ?? '');
    if (seconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  /// True when trying again really costs no second entry: a token was issued
  /// and has not expired (the server accepts it until its expiry second has
  /// passed). Without a token, or after it expired, the retry is counted like
  /// any other entry, so no promise is made. [now] is for tests.
  bool retryIsFree({DateTime? now}) {
    final expiry = tokenExpiry(voiceToken);
    if (expiry == null) return false;
    return !(now ?? DateTime.now()).toUtc().isAfter(expiry);
  }

  /// A failure worth offering "Try again" for: anything but a plan refusal,
  /// which the limit sheet explains and a retry could not change.
  static bool canRetryAfter(Object error) => error is! PlanLimitException;
}
