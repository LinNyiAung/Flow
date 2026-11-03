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

    group('the "no extra entry" hint is only shown while the voice token is valid', () {
      VoiceExtraction withToken(String? token) => VoiceExtraction(
            TranscriptionResult(transcription: 'coffee', voiceToken: token),
            extractor: (text, {voiceToken}) async => _result(),
          );
      final expiry = DateTime.utc(2026, 11, 3, 12, 0, 0);
      final token = '${expiry.millisecondsSinceEpoch ~/ 1000}.c2ln';

      test('before the expiry: the retry is free', () {
        final e = withToken(token);
        expect(e.retryIsFree(now: expiry.subtract(const Duration(minutes: 14))), isTrue);
        expect(e.retryIsFree(now: expiry.subtract(const Duration(seconds: 1))), isTrue);
      });

      test('exactly at the expiry second the server still accepts it', () {
        expect(withToken(token).retryIsFree(now: expiry), isTrue);
      });

      test('after the expiry: no promise', () {
        final e = withToken(token);
        expect(e.retryIsFree(now: expiry.add(const Duration(seconds: 1))), isFalse);
        expect(e.retryIsFree(now: expiry.add(const Duration(hours: 2))), isFalse);
      });

      test('without a token: no promise', () {
        expect(withToken(null).retryIsFree(now: expiry.subtract(const Duration(minutes: 1))), isFalse);
      });

      test('a token that does not look like one: no promise', () {
        final before = expiry.subtract(const Duration(minutes: 1));
        for (final bad in ['', 'garbage', '12345', '.sig', 'abc.sig', '-5.sig', '1700000000.']) {
          expect(withToken(bad).retryIsFree(now: before), isFalse, reason: bad);
        }
      });

      test('the expiry is read as unix seconds', () {
        expect(VoiceExtraction.tokenExpiry('1700000000.sig'), DateTime.utc(2023, 11, 14, 22, 13, 20));
        expect(VoiceExtraction.tokenExpiry(null), isNull);
      });

      test('the clock defaults to now: a token from the past is not free, one from the future is', () {
        final past = DateTime.now().toUtc().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000;
        final future = DateTime.now().toUtc().add(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000;
        expect(withToken('$past.sig').retryIsFree(), isFalse);
        expect(withToken('$future.sig').retryIsFree(), isTrue);
      });
    });

    test('the request body carries the token next to the exact transcript', () {
      expect(
        ApiService.extractTextBody('coffee 3 dollars', voiceToken: '1700000000.sig'),
        {'text': 'coffee 3 dollars', 'voice_token': '1700000000.sig'},
      );
    });
  });
}
