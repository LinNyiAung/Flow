import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/insight.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/plan_limit_text.dart';
import 'package:frontend/widgets/insight_notes.dart';
import 'package:intl/date_symbol_data_local.dart';

final _resets = DateTime(2026, 12, 1, 6);

void main() {
  group('planLimitText', () {
    setUpAll(() => initializeDateFormatting('my'));
    final en = AppLocalizations(const Locale('en'));
    final my = AppLocalizations(const Locale('my'));

    test('a reached limit names the feature and the reset date in the app language', () {
      final text = planLimitText(en,
          code: PlanLimitException.codeLimitReached,
          feature: 'insight_translation',
          resetsAt: _resets,
          fallbackMessage: 'It resets on Dec 1, 2026.');
      expect(text, contains(en.planLimitResetsOn(en.formatPlanDate(_resets))));
      expect(text, contains(en.knownPlanFeatureName('insight_translation')!));
      expect(text, isNot(contains('Dec 1, 2026'))); // not the server's date format

      final burmese = planLimitText(my,
          code: PlanLimitException.codeLimitReached,
          feature: 'insight_translation',
          resetsAt: _resets,
          fallbackMessage: 'It resets on Dec 1, 2026.');
      expect(burmese, contains(my.planLimitResetsOn(my.formatPlanDate(_resets))));
      expect(burmese, contains('၂၀၂၆')); // Myanmar digits
      expect(burmese, isNot(contains('Dec')));
      expect(burmese, isNot(contains('It resets')));
    });

    test('the cost cap reads the same for any feature, with the date', () {
      final text = planLimitText(en,
          code: PlanLimitException.codeCostCap, feature: 'insight_translation', resetsAt: _resets);
      expect(text, startsWith(en.planCostCapBody));
      expect(text, contains(en.formatPlanDate(_resets)));
    });

    test('a locked feature never shows a reset date', () {
      final text = planLimitText(en,
          code: PlanLimitException.codeLocked, feature: 'insight_translation', resetsAt: _resets);
      expect(text, en.planLimitLockedBody(en.knownPlanFeatureName('insight_translation')!));
    });

    test('the server message is used only for an unknown code or feature', () {
      expect(planLimitText(en, code: 'something_new', feature: 'chat', fallbackMessage: '  From the server  '),
          'From the server');
      expect(
          planLimitText(en,
              code: PlanLimitException.codeLimitReached, feature: 'unknown_feature', fallbackMessage: 'Server text'),
          'Server text');
      expect(planLimitText(en, code: 'something_new'), '');
    });
  });

  group('the Insights translation note is written by the app', () {
    Future<void> pumpNote(WidgetTester tester, TranslationUnavailable note, Locale locale) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('my')],
          home: Scaffold(
            body: Builder(
              builder: (context) => InsightTranslationNote(
                // What the Insights screen builds the note text with.
                message: planLimitText(
                  AppLocalizations.of(context),
                  code: note.code,
                  feature: 'insight_translation',
                  resetsAt: note.resetsAt,
                  fallbackMessage: note.message,
                ),
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final note = TranslationUnavailable(
      code: PlanLimitException.codeLimitReached,
      message: 'The server says it resets on Dec 1, 2026 (in the profile language).',
      resetsAt: _resets,
    );

    testWidgets('English', (tester) async {
      await pumpNote(tester, note, const Locale('en'));
      final text = tester.widget<Text>(find.byKey(const ValueKey('insight-translation-note'))).data!;
      final l = AppLocalizations(const Locale('en'));
      expect(text, contains(l.planLimitResetsOn(l.formatPlanDate(_resets))));
      expect(text, isNot(contains('The server says')));
    });

    testWidgets('Myanmar, even though the server message is English', (tester) async {
      await pumpNote(tester, note, const Locale('my'));
      final text = tester.widget<Text>(find.byKey(const ValueKey('insight-translation-note'))).data!;
      expect(text, contains('၂၀၂၆'));
      expect(text, isNot(contains('Dec')));
      expect(text, isNot(contains('The server says')));
    });
  });
}
