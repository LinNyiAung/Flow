import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/voice_image_models.dart';
import 'package:frontend/screens/transactions/voice_extraction.dart';
import 'package:frontend/services/api_service.dart';

MultipleExtractedTransactions _result() => MultipleExtractedTransactions(
      transactions: const [],
      totalCount: 0,
      overallConfidence: 0.9,
    );

void main() {
  group('retrying a failed voice extraction', () {
    test('the retry sends the same transcript and voice token, without a new transcription', () async {
      final calls = <(String, String?)>[];
      var fail = true;
      final extraction = VoiceExtraction(
        const TranscriptionResult(transcription: 'coffee 3 dollars', voiceToken: '1700000000.sig'),
        extractor: (text, {voiceToken}) async {
          calls.add((text, voiceToken));
          if (fail) throw ApiException('The AI service is unavailable.', statusCode: 503);
          return _result();
        },
      );

      await expectLater(extraction.extract(), throwsA(isA<ApiException>()));
      fail = false;
      final data = await extraction.extract();

      expect(data.totalCount, 0);
      expect(calls, [
        ('coffee 3 dollars', '1700000000.sig'),
        ('coffee 3 dollars', '1700000000.sig'),
      ]);
    });

    test('without a token (none issued) the retry still sends the transcript', () async {
      String? sentToken = 'unset';
      final extraction = VoiceExtraction(
        const TranscriptionResult(transcription: 'taxi 5000 kyats'),
        extractor: (text, {voiceToken}) async {
          sentToken = voiceToken;
          return _result();
        },
      );
      await extraction.extract();
      expect(sentToken, isNull);
    });

    test('only a plan refusal is not offered a retry', () {
      expect(VoiceExtraction.canRetryAfter(ApiException('boom', statusCode: 503)), isTrue);
      expect(VoiceExtraction.canRetryAfter(Exception('network')), isTrue);
      expect(
        VoiceExtraction.canRetryAfter(PlanLimitException(
          code: PlanLimitException.codeLimitReached,
          statusCode: 429,
          feature: 'entry',
        )),
        isFalse,
      );
    });

    test('the request body carries the token next to the exact transcript', () {
      expect(
        ApiService.extractTextBody('coffee 3 dollars', voiceToken: '1700000000.sig'),
        {'text': 'coffee 3 dollars', 'voice_token': '1700000000.sig'},
      );
    });
  });
}
