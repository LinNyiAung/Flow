import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/plan_limit_sheet.dart';

const _en = Locale('en');
const _my = Locale('my');

const _monthsMy = [
  'ဇန်နဝါရီ', 'ဖေဖော်ဝါရီ', 'မတ်', 'ဧပြီ', 'မေ', 'ဇွန်',
  'ဇူလိုင်', 'သြဂုတ်', 'စက်တင်ဘာ', 'အောက်တိုဘာ', 'နိုဝင်ဘာ', 'ဒီဇင်ဘာ',
];
const _monthsEn = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

PlanLimitException _error({
  String code = PlanLimitException.codeLimitReached,
  String? feature = 'chat',
  DateTime? resetsAt,
  String message = 'SERVER MESSAGE, Dec 1, 2026',
  bool upgradeAvailable = true,
}) =>
    PlanLimitException(
      code: code,
      statusCode: code == PlanLimitException.codeLocked ? 403 : 429,
      message: message,
      feature: feature,
      resetsAt: resetsAt,
      upgradeAvailable: upgradeAvailable,
    );

void main() {
  group('plan date formatter', () {
    test('English: day, full month name, year', () {
      final l = AppLocalizations(_en);
      expect(l.formatPlanDate(DateTime(2026, 12, 1)), '1 December 2026');
      expect(l.formatPlanDate(DateTime(2027, 1, 31, 23, 59)), '31 January 2027');
    });

    test('Myanmar: Burmese month names, the same order', () {
      final l = AppLocalizations(_my);
      expect(l.formatPlanDate(DateTime(2026, 12, 1)), '1 ဒီဇင်ဘာ 2026');
      expect(l.formatPlanDate(DateTime(2026, 8, 15)), '15 သြဂုတ် 2026');
    });

    test('all twelve months, both languages, follow the app\'s own month names', () {
      for (var m = 1; m <= 12; m++) {
        final date = DateTime(2026, m, 5);
        expect(AppLocalizations(_en).formatPlanDate(date), '5 ${_monthsEn[m - 1]} 2026');
        expect(AppLocalizations(_my).formatPlanDate(date), '5 ${_monthsMy[m - 1]} 2026');
        expect(_monthsMy[m - 1], AppLocalizations(_my).translate('month${_monthsEn[m - 1]}'));
      }
    });

    test('an instant is written in the device\'s local time', () {
      final instant = DateTime.utc(2026, 11, 9, 17, 30);
      final local = instant.toLocal();
      expect(AppLocalizations(_en).formatPlanDate(instant),
          '${local.day} ${_monthsEn[local.month - 1]} ${local.year}');
    });

    test('weekday form, both languages', () {
      final monday = DateTime(2026, 11, 9); // a Monday
      expect(AppLocalizations(_en).formatPlanDay(monday), 'Monday, 9 November');
      expect(AppLocalizations(_my).formatPlanDay(monday), 'တနင်္လာနေ့၊ 9 နိုဝင်ဘာ');
      expect(AppLocalizations(_en).formatPlanDay(DateTime(2026, 12, 1)), 'Tuesday, 1 December');
      expect(AppLocalizations(_en).formatPlanDay(DateTime(2026, 11, 15)), 'Sunday, 15 November');
      expect(AppLocalizations(_my).formatPlanDay(DateTime(2026, 11, 15)), 'တနင်္ဂနွေနေ့၊ 15 နိုဝင်ဘာ');
    });

    test('every weekday has a name in both languages', () {
      for (var d = 9; d <= 15; d++) {
        for (final locale in [_en, _my]) {
          final text = AppLocalizations(locale).formatPlanDay(DateTime(2026, 11, d));
          expect(text.contains('weekday'), isFalse, reason: text);
          expect(text.contains('{'), isFalse, reason: text);
        }
      }
    });

    test('Next insight line', () {
      expect(AppLocalizations(_en).insightNextOn('Monday, 10 November'),
          'Next insight: Monday, 10 November');
      expect(AppLocalizations(_my).insightNextOn('တနင်္လာနေ့၊ 10 နိုဝင်ဘာ'),
          contains('တနင်္လာနေ့၊ 10 နိုဝင်ဘာ'));
    });
  });

  group('limit sheet text', () {
    Future<void> open(WidgetTester tester, PlanLimitException error, Locale locale) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
          supportedLocales: const [_en, _my],
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanLimitSheet(error: error, onUpgrade: () {}, onClose: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String body(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('plan-limit-body'))).data!;

    final reset = DateTime(2026, 12, 1);

    testWidgets('limit reached, English: feature name from the app, reset date in words', (tester) async {
      await open(tester, _error(resetsAt: reset), _en);
      expect(body(tester), "You've used all of your AI chat. It resets on 1 December 2026.");
      expect(find.textContaining('SERVER MESSAGE'), findsNothing);
    });

    testWidgets('limit reached, Myanmar: whatever language the server wrote its message in', (tester) async {
      await open(tester, _error(resetsAt: reset), _my);
      final l = AppLocalizations(_my);
      expect(body(tester), '${l.planLimitReachedBody(l.planFeatureName('chat'))} '
          '${l.planLimitResetsOn('1 ဒီဇင်ဘာ 2026')}');
      expect(body(tester), contains('ဒီဇင်ဘာ'));
      expect(body(tester), isNot(contains('Dec')));
      expect(body(tester), isNot(contains('2026-12')));
    });

    testWidgets('cost cap: the monthly AI limit and when it resets', (tester) async {
      final error = _error(code: PlanLimitException.codeCostCap, feature: null, resetsAt: reset);
      await open(tester, error, _en);
      expect(body(tester), "You've reached this month's AI limit. It resets on 1 December 2026.");

      await open(tester, error, _my);
      final l = AppLocalizations(_my);
      expect(body(tester), '${l.planCostCapBody} ${l.planLimitResetsOn('1 ဒီဇင်ဘာ 2026')}');
    });

    testWidgets('cost cap without a date', (tester) async {
      await open(tester, _error(code: PlanLimitException.codeCostCap, feature: null), _en);
      expect(body(tester), "You've reached this month's AI limit.");
    });

    testWidgets('locked: says the feature is not in the plan, with no date', (tester) async {
      final error = _error(
          code: PlanLimitException.codeLocked, feature: 'insight_weekly', resetsAt: reset);
      await open(tester, error, _en);
      expect(body(tester), "Weekly insights isn't part of your plan.");

      await open(tester, error, _my);
      final l = AppLocalizations(_my);
      expect(body(tester), l.planLimitLockedBody(l.planFeatureName('insight_weekly')));
    });

    testWidgets('locked without a feature: needs a paid plan', (tester) async {
      await open(tester, _error(code: PlanLimitException.codeLocked, feature: null), _en);
      expect(body(tester), 'This feature is only available on the Plus and Pro plans.');
    });

    testWidgets('a code the app does not know falls back to the server message', (tester) async {
      await open(tester, _error(code: 'something_new', message: 'Server says hi.'), _en);
      expect(body(tester), 'Server says hi.');
    });

    testWidgets('a feature the app has no name for falls back to the server message', (tester) async {
      await open(tester, _error(feature: 'new_feature', message: 'Server says hi.'), _en);
      expect(body(tester), 'Server says hi.');
    });

    testWidgets('an unknown code with no message shows no body at all', (tester) async {
      await open(tester, _error(code: 'something_new', message: ''), _en);
      expect(find.byKey(const Key('plan-limit-body')), findsNothing);
    });
  });
}
