import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every request made through ApiService in this file gets [_respond]'s answer.
late http.Response Function(http.Request) _respond;
final _mock = MockClient((request) async => _respond(request));

Future<Object?> _errorOf(Future<void> Function() call) => http.runWithClient(() async {
      try {
        await call();
        return null;
      } catch (e) {
        return e;
      }
    }, () => _mock);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiService.currentLanguage = 'en';
  });
  tearDown(() => ApiService.currentLanguage = 'en');

  group('budget ideas: a failure with no message from the server', () {
    for (final lang in ['en', 'my']) {
      test('$lang: names Ko Toe Pwar, in the app language', () async {
        ApiService.currentLanguage = lang;
        final l = AppLocalizations(Locale(lang));
        _respond = (_) => http.Response('<html>Bad gateway</html>', 502);
        final error = await _errorOf(() => ApiService.getAIBudgetSuggestions(
              period: BudgetPeriod.monthly,
              startDate: DateTime(2026, 11, 1),
              currency: Currency.usd,
            ));
        expect(error, isA<ApiException>());
        expect((error as ApiException).message, '${l.budgetIdeasFailed} (502)');
        expect(error.message, contains(lang == 'en' ? 'Ko Toe Pwar' : 'ကိုတိုးပွား'));
        expect(error.message, isNot(contains('AI')));
      });
    }

    test("the server's own message still wins", () async {
      _respond = (_) => http.Response('{"detail":"Ko Toe Pwar can\'t suggest a budget right now."}', 503,
          headers: {'content-type': 'application/json'});
      final error = await _errorOf(() => ApiService.getAIBudgetSuggestions(
            period: BudgetPeriod.monthly,
            startDate: DateTime(2026, 11, 1),
            currency: Currency.usd,
          ));
      expect((error as ApiException).message, "Ko Toe Pwar can't suggest a budget right now.");
    });
  });
}
