import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/date_format.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  final now = DateTime(2026, 11, 10, 12);
  final morning = DateTime(2026, 11, 10, 7, 57);

  group('English', () {
    test('compact day: no year in the current year, year otherwise', () {
      expect(AppDates.compactDayIn(DateTime(2026, 11, 10), now: now), '10 Nov');
      expect(AppDates.compactDayIn(DateTime(2026, 8, 3), now: now), '3 Aug');
      expect(AppDates.compactDayIn(DateTime(2025, 12, 20), now: now), '20 Dec 2025');
    });

    test('full date and date with time', () {
      expect(AppDates.fullIn(DateTime(2026, 11, 10)), '10 Nov 2026');
      expect(AppDates.fullIn(DateTime(2027, 5, 30)), '30 May 2027');
      expect(AppDates.dateTimeIn(morning), '10 Nov 2026, 7:57 AM');
    });

    test('range: one year once, both years when they differ', () {
      expect(AppDates.rangeIn(DateTime(2026, 11, 1), DateTime(2026, 11, 30)), '1 Nov – 30 Nov 2026');
      expect(AppDates.rangeIn(DateTime(2025, 12, 20), DateTime(2026, 1, 19)), '20 Dec 2025 – 19 Jan 2026');
    });
  });

  group('Myanmar', () {
    setUpAll(() => initializeDateFormatting('my'));

    test('uses Myanmar month names, never English ones', () {
      final english = RegExp(r'Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|AM|PM');
      for (final text in [
        AppDates.compactDayIn(DateTime(2026, 11, 10), locale: 'my', now: now),
        AppDates.fullIn(DateTime(2026, 11, 10), locale: 'my'),
        AppDates.dateTimeIn(morning, locale: 'my'),
        AppDates.rangeIn(DateTime(2026, 11, 1), DateTime(2026, 11, 30), locale: 'my'),
      ]) {
        expect(text, isNot(matches(english)), reason: text);
        expect(text, isNotEmpty);
      }
    });
  });

  testWidgets('context forms follow the app locale', (tester) async {
    late String en;
    late String my;
    Widget app(Locale locale, void Function(String) out) => MaterialApp(
          locale: locale,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en'), Locale('my')],
          home: Builder(builder: (context) {
            out(AppDates.full(context, DateTime(2026, 11, 10)));
            return const SizedBox();
          }),
        );
    await tester.pumpWidget(app(const Locale('en'), (s) => en = s));
    await tester.pumpWidget(app(const Locale('my'), (s) => my = s));
    await tester.pumpAndSettle();
    expect(en, '10 Nov 2026');
    expect(my, AppDates.fullIn(DateTime(2026, 11, 10), locale: 'my'));
    expect(my, isNot(contains('Nov')));
  });
}
