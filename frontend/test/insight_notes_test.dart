import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/insight_notes.dart';

Future<void> _pump(WidgetTester tester, Widget child, {Locale locale = const Locale('en')}) async {
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
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('translation note', () {
    testWidgets('shows the message with a close button that has a tooltip', (tester) async {
      var closed = 0;
      await _pump(
        tester,
        InsightTranslationNote(message: 'Myanmar translation unavailable.', onClose: () => closed++),
      );

      expect(find.byKey(const ValueKey('insight-translation-note')), findsOneWidget);
      expect(find.text('Myanmar translation unavailable.'), findsOneWidget);
      final close = find.byKey(const ValueKey('insight-translation-note-close'));
      expect(close, findsOneWidget);
      expect(find.byTooltip(AppLocalizations(const Locale('en')).close), findsOneWidget);

      await tester.tap(close);
      expect(closed, 1);
    });

    testWidgets('the tooltip is in the app language', (tester) async {
      await _pump(
        tester,
        InsightTranslationNote(message: 'x', onClose: () {}),
        locale: const Locale('my'),
      );
      expect(find.byTooltip(AppLocalizations(const Locale('my')).close), findsOneWidget);
    });

    testWidgets('closing through a parent that rebuilds removes the note', (tester) async {
      var shown = true;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
          supportedLocales: const [Locale('en'), Locale('my')],
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: shown
                  ? InsightTranslationNote(
                      message: 'Unavailable', onClose: () => setState(() => shown = false))
                  : const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('insight-translation-note-close')));
      await tester.pumpAndSettle();
      expect(find.text('Unavailable'), findsNothing);
    });
  });

  group('next insight line', () {
    testWidgets('English: Next insight: Monday, 10 November', (tester) async {
      await _pump(tester, NextInsightLine(nextAt: DateTime(2026, 11, 9, 5), now: DateTime(2026, 11, 3)));
      expect(find.byKey(const ValueKey('insight-next')), findsOneWidget);
      expect(find.text('Next insight: Monday, 9 November'), findsOneWidget);
    });

    testWidgets('hidden once the date has passed (the app was left open over the run time)', (tester) async {
      await _pump(tester, NextInsightLine(nextAt: DateTime(2026, 11, 9, 5), now: DateTime(2026, 11, 9, 5, 0, 1)));
      expect(find.byKey(const ValueKey('insight-next')), findsNothing);
      await _pump(tester, NextInsightLine(nextAt: DateTime(2026, 11, 9, 5), now: DateTime(2026, 11, 9, 5)));
      expect(find.byKey(const ValueKey('insight-next')), findsNothing);
      await _pump(tester, NextInsightLine(nextAt: DateTime(2026, 11, 9, 5), now: DateTime(2026, 11, 9, 4, 59, 59)));
      expect(find.byKey(const ValueKey('insight-next')), findsOneWidget);
    });

    testWidgets('Myanmar: weekday and Burmese month', (tester) async {
      await _pump(tester, NextInsightLine(nextAt: DateTime(2026, 12, 1, 6), now: DateTime(2026, 11, 3)),
          locale: const Locale('my'));
      final text = tester.widget<Text>(find.byKey(const ValueKey('insight-next'))).data!;
      expect(text, contains('အင်္ဂါနေ့၊ 1 ဒီဇင်ဘာ'));
      expect(text, isNot(contains('Next')));
    });

    testWidgets('nothing when the server sent no date', (tester) async {
      await _pump(tester, const NextInsightLine(nextAt: null));
      expect(find.byKey(const ValueKey('insight-next')), findsNothing);
    });
  });
}
