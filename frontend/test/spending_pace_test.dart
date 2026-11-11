import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/spending_pace.dart';
import 'package:frontend/widgets/spending_pace_card.dart';

final _today = DateTime(2026, 11, 5, 14, 30); // a Thursday

Transaction _tx(
  DateTime date,
  double amount, {
  Currency currency = Currency.mmk,
  TransactionType type = TransactionType.outflow,
}) =>
    Transaction(
      id: '${date.toIso8601String()}-$amount-${currency.name}',
      userId: 'u1',
      type: type,
      mainCategory: 'Food',
      subCategory: 'Lunch',
      date: date,
      amount: amount,
      currency: currency,
      createdAt: date,
      updatedAt: date,
    );

Future<List<(DateTime, Currency)>> _pumpCard(
  WidgetTester tester,
  List<Transaction> outflows, {
  Currency defaultCurrency = Currency.mmk,
  Locale locale = const Locale('en'),
}) async {
  final opened = <(DateTime, Currency)>[];
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
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SpendingPaceCard(
            outflows: outflows,
            defaultCurrency: defaultCurrency,
            today: _today,
            onSeeTransactions: (day, currency) => opened.add((day, currency)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

Finder _bar(int index) => find.byKey(ValueKey('spending-pace-bar-$index'));

// The bars share one gesture detector, so tap where the bar is drawn.
Future<void> _tapBar(WidgetTester tester, int index) => tester.tapAt(tester.getCenter(_bar(index)));

void main() {
  group('buildSpendingPace', () {
    test('buckets outflows by calendar day for the last 7 days, per currency', () {
      final pace = buildSpendingPace([
        _tx(DateTime(2026, 11, 5, 9), 1000),
        _tx(DateTime(2026, 11, 5, 20), 500),
        _tx(DateTime(2026, 11, 3), 2000),
        _tx(DateTime(2026, 10, 30), 300), // first day of the window
        _tx(DateTime(2026, 10, 29), 999), // just outside
        _tx(DateTime(2026, 11, 4), 7, currency: Currency.usd),
        _tx(DateTime(2026, 11, 4), 50000, type: TransactionType.inflow),
      ], today: _today);

      expect(pace.days.first, DateTime(2026, 10, 30));
      expect(pace.days.last, DateTime(2026, 11, 5));
      expect(pace.totalsFor(Currency.mmk), [300, 0, 0, 0, 2000, 0, 1500]);
      expect(pace.totalsFor(Currency.usd), [0, 0, 0, 0, 0, 7, 0]);
      expect(pace.totalsFor(Currency.thb), List<double>.filled(7, 0));
    });

    test('currency options put the default first and only list currencies with spending', () {
      final pace = buildSpendingPace([
        _tx(DateTime(2026, 11, 5), 7, currency: Currency.usd),
        _tx(DateTime(2026, 11, 4), 10, currency: Currency.thb),
        _tx(DateTime(2026, 11, 4), 1000),
      ], today: _today);

      expect(pace.currencyOptions(Currency.thb), [Currency.thb, Currency.usd, Currency.mmk]);
    });

    test('with no spending the default currency is the only option', () {
      final pace = buildSpendingPace([], today: _today);
      expect(pace.currencyOptions(Currency.usd), [Currency.usd]);
    });

    test('a default currency with no spending is not offered when another has some', () {
      final pace = buildSpendingPace([
        _tx(DateTime(2026, 11, 5), 7, currency: Currency.usd),
      ], today: _today);
      expect(pace.currencyOptions(Currency.mmk), [Currency.usd]);
    });
  });

  group('SpendingPaceCard', () {
    testWidgets('starts with today selected and shows its total', (tester) async {
      await _pumpCard(tester, [
        _tx(DateTime(2026, 11, 5, 9), 45000),
        _tx(DateTime(2026, 11, 3), 12500),
      ]);

      expect(find.textContaining('Today · K45,000.00'), findsOneWidget);
      expect(find.text('See transactions'), findsOneWidget);
    });

    testWidgets('tapping a bar selects that day', (tester) async {
      await _pumpCard(tester, [
        _tx(DateTime(2026, 11, 5, 9), 45000),
        _tx(DateTime(2026, 11, 3), 12500),
      ]);

      await _tapBar(tester, 4); // Tue 3 Nov
      await tester.pumpAndSettle();

      expect(find.textContaining('Tue, 3 Nov · K12,500.00'), findsOneWidget);
      expect(find.textContaining('Today'), findsNothing);
    });

    testWidgets('a day with no spending says so and has no link', (tester) async {
      await _pumpCard(tester, [_tx(DateTime(2026, 11, 5), 45000)]);

      await _tapBar(tester, 0); // Fri 30 Oct
      await tester.pumpAndSettle();

      expect(find.textContaining('Fri, 30 Oct · Nothing spent'), findsOneWidget);
      expect(find.text('See transactions'), findsNothing);
    });

    testWidgets('dragging across the bars moves the selection', (tester) async {
      await _pumpCard(tester, [
        _tx(DateTime(2026, 11, 1), 800),
        _tx(DateTime(2026, 11, 5), 45000),
      ]);

      final start = tester.getCenter(_bar(6));
      final end = tester.getCenter(_bar(2)); // Sun 1 Nov
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(Offset.lerp(start, end, 0.5)!);
      await gesture.moveTo(end);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.textContaining('Sun, 1 Nov · K800.00'), findsOneWidget);
    });

    testWidgets('See transactions opens the selected day in the shown currency', (tester) async {
      final opened = await _pumpCard(tester, [
        _tx(DateTime(2026, 11, 3), 12500),
      ]);

      await _tapBar(tester, 4);
      await tester.pumpAndSettle();
      await tester.tap(find.text('See transactions'));
      await tester.pumpAndSettle();

      expect(opened, [(DateTime(2026, 11, 3), Currency.mmk)]);
    });

    testWidgets('shows one currency at a time, with a switch only when there are several', (tester) async {
      await _pumpCard(tester, [
        _tx(DateTime(2026, 11, 5), 45000),
        _tx(DateTime(2026, 11, 5), 7, currency: Currency.usd),
      ]);

      // Not added together: 45000 + 7 would be 45,007.
      expect(find.textContaining('Today · K45,000.00'), findsOneWidget);
      expect(find.byKey(const ValueKey('spending-pace-currency-mmk')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('spending-pace-currency-usd')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Today · \$7.00'), findsOneWidget);
    });

    testWidgets('no currency switch with a single currency', (tester) async {
      await _pumpCard(tester, [_tx(DateTime(2026, 11, 5), 45000)]);
      expect(find.byKey(const ValueKey('spending-pace-currency-mmk')), findsNothing);
    });

    testWidgets('shows the only currency with spending when it is not the default', (tester) async {
      await _pumpCard(tester, [_tx(DateTime(2026, 11, 5), 7, currency: Currency.usd)],
          defaultCurrency: Currency.mmk);
      expect(find.textContaining('Today · \$7.00'), findsOneWidget);
    });

    testWidgets('new data resets the selection to today', (tester) async {
      Widget card(List<Transaction> outflows) => MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('my')],
            home: Scaffold(
              body: SpendingPaceCard(
                outflows: outflows,
                defaultCurrency: Currency.mmk,
                today: _today,
              ),
            ),
          );
      await tester.pumpWidget(card([_tx(DateTime(2026, 11, 3), 12500)]));
      await tester.pumpAndSettle();
      await _tapBar(tester, 4);
      await tester.pumpAndSettle();
      expect(find.textContaining('Tue, 3 Nov'), findsOneWidget);

      await tester.pumpWidget(card([_tx(DateTime(2026, 11, 3), 12500), _tx(DateTime(2026, 11, 5), 10)]));
      await tester.pumpAndSettle();
      expect(find.textContaining('Today · K10.00'), findsOneWidget);
    });

    testWidgets('each bar is a selectable button for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpCard(tester, [_tx(DateTime(2026, 11, 3), 12500)]);

      final bar = tester.getSemantics(_bar(4));
      expect(bar.label, contains('Tue, 3 Nov'));
      expect(bar.label, contains('K12,500.00'));
      expect(bar.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(tester.getSemantics(_bar(6)).getSemanticsData().hasFlag(SemanticsFlag.isSelected), isTrue);

      tester.semantics.tap(find.semantics.byLabel(RegExp('Tue, 3 Nov')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tue, 3 Nov · K12,500.00'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('Myanmar shows the Myanmar wording', (tester) async {
      await _pumpCard(tester, [_tx(DateTime(2026, 11, 5), 45000)], locale: const Locale('my'));
      expect(find.textContaining('ယနေ့'), findsOneWidget);
      expect(find.text('See transactions'), findsNothing);
    });

    // Fri 30 Oct .. Thu 5 Nov.
    List<String> weekdayLabels(WidgetTester tester) => [
          for (var i = 0; i < 7; i++)
            tester
                .widgetList<Text>(find.byType(Text))
                .where((t) => t.textAlign == TextAlign.center)
                .elementAt(i)
                .data!,
        ];

    testWidgets('weekday letters under the bars', (tester) async {
      await _pumpCard(tester, [_tx(DateTime(2026, 11, 5), 45000)]);
      expect(weekdayLabels(tester), ['F', 'S', 'S', 'M', 'T', 'W', 'T']);
    });

    testWidgets('Myanmar weekday labels under the bars', (tester) async {
      await _pumpCard(tester, [_tx(DateTime(2026, 11, 5), 45000)], locale: const Locale('my'));
      expect(weekdayLabels(tester), ['ကြာ', 'နေ', 'နွေ', 'လာ', 'ဂါ', 'ဟူး', 'တေး']);
    });

    testWidgets('currency chips sit at the right edge of the card', (tester) async {
      await _pumpCard(tester, [
        _tx(DateTime(2026, 11, 5), 45000),
        _tx(DateTime(2026, 11, 5), 7, currency: Currency.usd),
      ]);
      final card = tester.getRect(find.byType(Card));
      final lastChip = tester.getRect(find.byKey(const ValueKey('spending-pace-currency-usd')));
      // The card's own 4 px margin, then its 18 px padding.
      expect(lastChip.right, closeTo(card.right - 4 - 18, 1));
    });

    testWidgets('Myanmar 360: the chips wrap under the title without overflow', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await _pumpCard(
        tester,
        [_tx(DateTime(2026, 11, 5), 45000), _tx(DateTime(2026, 11, 5), 7, currency: Currency.usd)],
        locale: const Locale('my'),
      );
      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(Card));
      final lastChip = tester.getRect(find.byKey(const ValueKey('spending-pace-currency-usd')));
      expect(lastChip.right, lessThanOrEqualTo(card.right));
    });
  });
}
