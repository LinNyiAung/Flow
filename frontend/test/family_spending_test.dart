import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/models/family_spending.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/family/family_spending_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/money.dart';
import 'package:frontend/widgets/app_drawer.dart';
import 'package:frontend/widgets/mascot.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _en = AppLocalizations(const Locale('en'));
final _my = AppLocalizations(const Locale('my'));

FamilySpendingRow _row(String? id, String name, double amount, double previous, {String status = 'active'}) =>
    FamilySpendingRow(memberId: id, displayName: name, status: status, amount: amount, previousAmount: previous);

FamilySpendingOverview _overview(
  DateTime month, {
  Currency currency = Currency.mmk,
  List<FamilySpendingRow>? rows,
  double? total,
  double previousTotal = 0,
  List<Currency> currencies = const [Currency.mmk, Currency.usd],
  DateTime? firstMonth,
}) {
  final r = rows ??
      [
        _row(null, 'Whole family', 50000, 40000),
        _row('mama', 'Ma Ma', 42000, 30000),
        _row('mum', 'Mum', 8000, 0),
      ];
  return FamilySpendingOverview(
    currency: currency,
    month: month,
    total: total ?? r.fold(0.0, (s, x) => s + x.amount),
    previousTotal: previousTotal,
    rows: r,
    currencies: currencies,
    firstMonth: firstMonth ?? DateTime(2025, 2),
  );
}

/// Records each call; answers with [answer] (default: [_overview] for the month and currency asked).
class _Loader {
  _Loader([this.answer]);
  final FamilySpendingOverview Function(DateTime month, Currency? currency)? answer;
  final calls = <(DateTime, Currency?)>[];

  Future<FamilySpendingOverview> call(DateTime month, {Currency? currency}) async {
    calls.add((month, currency));
    return (answer ?? (m, c) => _overview(m, currency: c ?? Currency.mmk))(month, currency);
  }
}

Future<void> _pump(WidgetTester tester, _Loader loader, {Locale locale = const Locale('en')}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('my')],
    home: FamilySpendingScreen(loader: loader.call, now: () => DateTime(2025, 4, 18, 10)),
  ));
  await tester.pumpAndSettle();
}

class _FakeFamily extends FamilyProvider {
  _FakeFamily(this.member);
  final bool member;
  @override
  Family? get family => member ? const Family(id: 'f1', name: 'Aung family') : null;
  @override
  bool get inFamily => member;
  @override
  bool get loaded => true;
}

class _FakeNotifications extends NotificationProvider {
  @override
  Future<void> fetchUnreadCount() async {}
}

void main() {
  group('models', () {
    test('the overview and its rows parse from the server JSON', () {
      final o = FamilySpendingOverview.fromJson({
        'currency': 'mmk',
        'month': '2025-04',
        'total': 42000,
        'previous_total': 160000.0,
        'rows': [
          {'member_id': null, 'display_name': 'Whole family', 'status': 'active', 'amount': 1, 'previous_amount': 0},
          {'member_id': 'd', 'display_name': 'Dad', 'status': 'former', 'amount': 3.34, 'previous_amount': 2},
        ],
        'currencies': ['mmk', 'usd'],
        'first_month': '2025-03',
      });
      expect(o.currency, Currency.mmk);
      expect(o.month, DateTime(2025, 4));
      expect([o.total, o.previousTotal], [42000.0, 160000.0]);
      expect(o.rows.first.isWholeFamily, isTrue);
      expect(o.rows.last.isFormer, isTrue);
      expect(o.rows.last.previousAmount, 2.0);
      expect(o.currencies, [Currency.mmk, Currency.usd]);
      expect(o.firstMonth, DateTime(2025, 3));
      expect(FamilySpendingOverview.fromJson({'currency': 'usd', 'month': '2025-01', 'first_month': null}).firstMonth,
          isNull);
    });

    test('spendingChange: up, down, same, new, nothing', () {
      expect(spendingChange(_en, 42000, 30000), '▲ 40%');
      expect(spendingChange(_en, 9000, 10000), '▼ 10%');
      expect(spendingChange(_en, 5, 5), '0%');
      expect(spendingChange(_en, 5, 0), _en.familySpendingNew);
      expect(spendingChange(_en, 0, 0), isNull);
    });
  });

  group('the month screen', () {
    testWidgets('opens on the current month and lists rows largest first', (tester) async {
      final loader = _Loader();
      await _pump(tester, loader);
      expect(loader.calls.single, (DateTime(2025, 4), null));
      expect(find.text('April 2025'), findsOneWidget);
      final names = [_en.wholeFamily, 'Ma Ma', 'Mum'];
      final ys = [for (final n in names) tester.getTopLeft(find.text(n)).dy];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(find.text('Whole family'), findsOneWidget); // the app's string, once
      expect(find.text(formatMoney(42000, Currency.mmk)), findsOneWidget);
      expect(find.text('42%'), findsOneWidget); // 42,000 of 100,000
      expect(find.text('▲ 40%'), findsOneWidget);
      expect(find.text(_en.familySpendingNew), findsOneWidget);
    });

    testWidgets('month arrows move and stop at the bounds', (tester) async {
      final loader = _Loader((m, c) => _overview(m, firstMonth: DateTime(2025, 3)));
      await _pump(tester, loader);
      final next = find.byKey(const Key('family-spending-next'));
      final prev = find.byKey(const Key('family-spending-prev'));
      expect(tester.widget<IconButton>(next).onPressed, isNull, reason: 'April 2025 is the current month');
      await tester.tap(prev);
      await tester.pumpAndSettle();
      expect(loader.calls.last.$1, DateTime(2025, 3));
      expect(find.text('March 2025'), findsOneWidget);
      expect(tester.widget<IconButton>(prev).onPressed, isNull, reason: 'March 2025 is the first month');
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(loader.calls.last.$1, DateTime(2025, 4));
    });

    testWidgets('currency picker lists only currencies with spending', (tester) async {
      final loader = _Loader();
      await _pump(tester, loader);
      await tester.tap(find.byKey(const Key('family-spending-currency')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('family-spending-currency-usd')), findsOneWidget);
      expect(find.byKey(const Key('family-spending-currency-thb')), findsNothing);
      await tester.tap(find.byKey(const Key('family-spending-currency-usd')));
      await tester.pumpAndSettle();
      expect(loader.calls.last, (DateTime(2025, 4), Currency.usd));
    });

    testWidgets('a former member is marked former', (tester) async {
      await _pump(tester, _Loader((m, c) => _overview(m, rows: [_row('d', 'Dad', 10, 0, status: 'former')])));
      expect(find.text(_en.familyFormerName('Dad')), findsOneWidget);
    });

    testWidgets('an empty month says so plainly, without Ko Toe Pwar', (tester) async {
      await _pump(tester, _Loader((m, c) => _overview(m, rows: const [])));
      expect(find.text(_en.familySpendingNoneThisMonth), findsOneWidget);
      expect(find.byType(Mascot), findsNothing);
    });

    testWidgets('no family spending at all shows Ko Toe Pwar', (tester) async {
      await _pump(tester, _Loader((m, c) => _overview(m, rows: const [], currencies: const [])));
      expect(find.text(_en.familySpendingNoneYet), findsOneWidget);
      expect(find.byType(Mascot), findsOneWidget);
    });

    testWidgets('Myanmar: the month and the rows render', (tester) async {
      await _pump(tester, _Loader(), locale: const Locale('my'));
      expect(find.text(_my.wholeFamily), findsOneWidget);
      expect(find.text(_my.familySpendingTotal), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the drawer', () {
    Future<void> pumpDrawer(WidgetTester tester, bool member) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PlanProvider(loader: () async => PlanStatus(plan: Plan.free))),
          ChangeNotifierProvider(create: (_) => BookModeProvider()),
          ChangeNotifierProvider<FamilyProvider>(create: (_) => _FakeFamily(member)),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => _FakeNotifications()),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('my')],
          routes: {'/family-spending': (_) => const Scaffold(body: Text('family spending page'))},
          home: Scaffold(drawer: AppDrawer(), body: const SizedBox()),
        ),
      ));
      await tester.pumpAndSettle();
      final state = tester.state<ScaffoldState>(find.byType(Scaffold).first);
      state.openDrawer();
      await tester.pumpAndSettle();
    }

    testWidgets('outside a family there is no Family spending item', (tester) async {
      await pumpDrawer(tester, false);
      expect(find.text(_en.familySpending), findsNothing);
    });

    testWidgets('in a family it is there and opens the screen', (tester) async {
      await pumpDrawer(tester, true);
      await tester.ensureVisible(find.text(_en.familySpending));
      await tester.tap(find.text(_en.familySpending));
      await tester.pumpAndSettle();
      expect(find.text('family spending page'), findsOneWidget);
    });
  });

  test('every new string has a Myanmar text of its own', () {
    final getters = <String Function(AppLocalizations)>[
      (l) => l.familySpending,
      (l) => l.familySpendingTotal,
      (l) => l.familySpendingVsLast('Mar'),
      (l) => l.familySpendingNew,
      (l) => l.familySpendingNoneThisMonth,
      (l) => l.familySpendingNoneYet,
      (l) => l.familySpendingCurrency,
    ];
    for (final get in getters) {
      final english = get(_en);
      final myanmar = get(_my);
      expect(english, isNot(startsWith('familySpending')), reason: english);
      expect(myanmar.trim(), isNotEmpty);
      expect(myanmar, isNot(english), reason: english);
    }
  });
}
