import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/voice_image_models.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/widgets/amount_entry_dialog.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/insight_errors.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('insight error mapping', () {
    final l = AppLocalizations(const Locale('en'));

    test('429 maps to rate limited', () {
      expect(insightErrorMessage(429, l), l.insightsRateLimited);
    });

    test('5xx maps to server error, 502/503 to temporarily unavailable', () {
      expect(insightErrorMessage(500, l), l.insightsServerError);
      expect(insightErrorMessage(504, l), l.insightsServerError);
      expect(insightErrorMessage(502, l), l.insightsTemporarilyUnavailable);
      expect(insightErrorMessage(503, l), l.insightsTemporarilyUnavailable);
    });

    test('legacy 500 mentioning 429 still maps to rate limited', () {
      expect(
        insightErrorMessage(500, l,
            rawMessage: 'Failed to generate insights: 429 RESOURCE_EXHAUSTED'),
        l.insightsRateLimited,
      );
      expect(
        insightErrorMessage(null, l, rawMessage: 'Failed to get insights: 429: quota'),
        l.insightsRateLimited,
      );
      // Digits that merely contain 429 are not a rate limit.
      expect(insightErrorMessage(500, l, rawMessage: 'Order 14290 failed'),
          l.insightsServerError);
    });

    test('other / unknown status maps to generic error', () {
      expect(insightErrorMessage(400, l), l.insightsGenericError);
      expect(insightErrorMessage(null, l), l.insightsGenericError);
    });
  });

  group('session rejection vs transient failure', () {
    test('401 and unverified 403 sign the user out', () {
      expect(ApiService.isSessionRejection(ApiException('x', statusCode: 401)),
          isTrue);
      expect(ApiService.isSessionRejection(EmailNotVerifiedException('x')),
          isTrue);
      expect(
          ApiService.isSessionRejection(
              ApiException('Email not verified', statusCode: 403)),
          isTrue);
    });

    test('timeouts, network and server errors keep the session', () {
      expect(ApiService.isSessionRejection(ApiException('timed out')), isFalse);
      expect(ApiService.isSessionRejection(ApiException('x', statusCode: 500)),
          isFalse);
      expect(ApiService.isSessionRejection(ApiException('x', statusCode: 403)),
          isFalse);
      expect(ApiService.isSessionRejection(Exception('boom')), isFalse);
    });
  });

  group('request timeouts', () {
    Duration t(String path) =>
        ApiService.timeoutFor(Uri.parse('https://x.test$path'));

    test('auth and version check survive a cold start', () {
      expect(t('/api/auth/me'), const Duration(seconds: 60));
      expect(t('/api/auth/login'), const Duration(seconds: 60));
      expect(t('/api/app/check-version'), const Duration(seconds: 60));
      expect(t('/api/app/latest-android'), const Duration(seconds: 60));
    });

    test('insights get the longest timeout', () {
      expect(t('/api/insights'), const Duration(seconds: 180));
      expect(t('/api/insights/regenerate'), const Duration(seconds: 180));
    });

    test('other endpoints keep their timeouts', () {
      expect(t('/api/chat/history'), const Duration(seconds: 90));
      expect(t('/api/transactions'), const Duration(seconds: 20));
    });
  });

  group('language sync decision', () {
    test('no pending change: server value wins', () {
      final d = LanguageSyncDecision.decide(
        userId: 'u1',
        serverLanguage: 'my',
        localLanguage: 'en',
        pendingUserId: null,
      );
      expect(d.apply, 'my');
      expect(d.push, isFalse);
      expect(d.clearPending, isFalse);
    });

    test('own pending change: local wins and is pushed again', () {
      final d = LanguageSyncDecision.decide(
        userId: 'u1',
        serverLanguage: 'en',
        localLanguage: 'my',
        pendingUserId: 'u1',
      );
      expect(d.apply, isNull);
      expect(d.push, isTrue);
    });

    test('pending change already on the server: marker cleared', () {
      final d = LanguageSyncDecision.decide(
        userId: 'u1',
        serverLanguage: 'my',
        localLanguage: 'my',
        pendingUserId: 'u1',
      );
      expect(d.apply, isNull);
      expect(d.push, isFalse);
      expect(d.clearPending, isTrue);
    });

    test("another account's marker is dropped and server value applied", () {
      final d = LanguageSyncDecision.decide(
        userId: 'u2',
        serverLanguage: 'en',
        localLanguage: 'my',
        pendingUserId: 'u1',
      );
      expect(d.apply, 'en');
      expect(d.push, isFalse);
      expect(d.clearPending, isTrue);
    });

    test('invalid server value leaves the local choice alone', () {
      final d = LanguageSyncDecision.decide(
        userId: 'u1',
        serverLanguage: null,
        localLanguage: 'my',
        pendingUserId: null,
      );
      expect(d.apply, isNull);
      expect(d.push, isFalse);
    });

    test('pending marker round-trips through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await LocalizationService.getLanguageSyncPendingUser(), isNull);
      await LocalizationService.setLanguageSyncPendingUser('u1');
      expect(await LocalizationService.getLanguageSyncPendingUser(), 'u1');
      await LocalizationService.setLanguageSyncPendingUser(null);
      expect(await LocalizationService.getLanguageSyncPendingUser(), isNull);
    });
  });

  group('extracted items without an amount', () {
    Map<String, dynamic> item(num amount) => {
          'type': 'outflow',
          'main_category': 'Food',
          'sub_category': 'Groceries',
          'date': '2026-10-09T00:00:00+00:00',
          'amount': amount,
          'currency': 'mmk',
          'confidence': 0,
          'reasoning': 'Could not read the amount',
        };

    test('amount 0 needs input until a positive amount is entered', () {
      final t = ExtractedTransactionData.fromJson(item(0));
      expect(t.needsAmount, isTrue);
      final fixed = t.copyWith(amount: 1500);
      expect(fixed.needsAmount, isFalse);
      expect(fixed.toJson()['amount'], 1500);
      expect(ExtractedTransactionData.fromJson(item(2.5)).needsAmount, isFalse);
    });

    test('multiple extraction tolerates an empty list', () {
      final m = MultipleExtractedTransactions.fromJson({
        'transactions': [],
        'overall_confidence': 0,
        'analysis': '2 items omitted',
      });
      expect(m.transactions, isEmpty);
      expect(m.totalCount, 0);
      expect(m.analysis, '2 items omitted');
    });

    test('amount entry accepts only positive numbers', () {
      expect(parsePositiveAmount('1500'), 1500);
      expect(parsePositiveAmount('1,500.50'), 1500.5);
      expect(parsePositiveAmount('0'), isNull);
      expect(parsePositiveAmount('0.00'), isNull);
      expect(parsePositiveAmount('1.234'), isNull);
      expect(parsePositiveAmount('abc'), isNull);
    });

    test('a single comma followed by 1-2 digits is a decimal comma', () {
      expect(parsePositiveAmount('12,50'), 12.5);
      expect(parsePositiveAmount('12,5'), 12.5);
      expect(parsePositiveAmount('0,75'), 0.75);
      expect(parsePositiveAmount(' 1500,05 '), 1500.05);
    });

    test('otherwise commas are thousands grouping', () {
      expect(parsePositiveAmount('1,500'), 1500);
      expect(parsePositiveAmount('1,500,000'), 1500000);
      expect(parsePositiveAmount('12,345.6'), 12345.6);
    });

    test('ambiguous comma input is rejected with a reason', () {
      for (final input in ['1,5000', '12,345,67', '1,50.5', '1,2,3', ',50', '1,']) {
        expect(parsePositiveAmount(input), isNull, reason: input);
        expect(parseAmountInput(input).error, AmountInputError.ambiguous,
            reason: input);
      }
      expect(parseAmountInput('0,00').error, AmountInputError.notPositive);
      expect(parseAmountInput('abc').error, AmountInputError.invalid);
      expect(parseAmountInput('').error, AmountInputError.invalid);
    });
  });

  group('token removal', () {
    test('an older logout never removes a newer login token', () async {
      SharedPreferences.setMockInitialValues({'access_token': 'new'});
      await ApiService.removeTokenIfMatches('old');
      expect(await ApiService.getToken(), 'new');
      await ApiService.removeTokenIfMatches('new');
      expect(await ApiService.getToken(), isNull);
    });
  });
}
