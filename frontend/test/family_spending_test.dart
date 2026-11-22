import 'package:fl_chart/fl_chart.dart';
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
import 'package:frontend/screens/family/family_person_spending_screen.dart';
import 'package:frontend/screens/family/family_spending_screen.dart';
import 'package:frontend/services/api_service.dart';
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

  group('the person screen', () {
    FamilyPersonSpending person({String? id = 'mama', String name = 'Ma Ma'}) => FamilyPersonSpending(
          currency: Currency.mmk,
          month: DateTime(2025, 4),
          memberId: id,
          displayName: name,
          amount: 42000,
          previousAmount: 30000,
          categories: const [
            CategorySpending(mainCategory: 'Food & Daily Living', amount: 42000, subCategories: [
              SubCategorySpending(subCategory: 'Groceries', amount: 30000),
              SubCategorySpending(subCategory: 'Restaurants', amount: 12000),
            ]),
            CategorySpending(mainCategory: 'Shopping & Lifestyle', amount: 5000, subCategories: [
              SubCategorySpending(subCategory: 'Clothing', amount: 5000),
            ]),
          ],
          trend: [
            for (var i = 0; i < 6; i++)
              MonthAmount(month: DateTime(2024, 11 + i), amount: i == 5 ? 42000 : (i == 4 ? 30000 : 0)),
          ],
          topEntries: [
            SpendingEntry(
                id: 'e1', date: DateTime(2025, 4, 30), mainCategory: 'Food & Daily Living', subCategory: 'Groceries',
                description: 'Market run', amount: 90000, share: 30000, splitBetween: 3),
            SpendingEntry(
                id: 'e2', date: DateTime(2025, 4, 20), mainCategory: 'Food & Daily Living', subCategory: 'Restaurants',
                description: 'Lunch', amount: 12000, share: 12000, splitBetween: 1),
          ],
          addedBy: const [
            AddedByCount(memberId: 'mum', displayName: 'Mum', count: 6),
            AddedByCount(memberId: 'dad', displayName: 'Dad', count: 2),
          ],
        );

    Future<List<(DateTime, String?, Currency?)>> pumpPerson(WidgetTester tester,
        {FamilyPersonSpending? data, Object? failFirst, String? memberId = 'mama', String name = 'Ma Ma'}) async {
      final calls = <(DateTime, String?, Currency?)>[];
      var failed = false;
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390 * 3, 2000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('my')],
        home: FamilyPersonSpendingScreen(
          month: DateTime(2025, 4),
          currency: Currency.mmk,
          memberId: memberId,
          displayName: name,
          loader: (month, {memberId, currency}) async {
            calls.add((month, memberId, currency));
            if (failFirst != null && !failed) {
              failed = true;
              throw failFirst;
            }
            return data ?? person();
          },
        ),
      ));
      await tester.pumpAndSettle();
      return calls;
    }

    testWidgets("shows the person's month and change", (tester) async {
      final calls = await pumpPerson(tester);
      expect(calls.single, (DateTime(2025, 4), 'mama', Currency.mmk));
      expect(find.text('Ma Ma'), findsWidgets);
      expect(find.text(formatMoney(42000, Currency.mmk)), findsWidgets);
      expect(find.textContaining('▲ 40%'), findsOneWidget);
    });

    testWidgets('Whole family shows the app string', (tester) async {
      await pumpPerson(tester, data: person(id: null, name: 'Whole family'), memberId: null, name: 'Whole family');
      expect(find.text(_en.wholeFamily), findsWidgets);
    });

    testWidgets('categories largest first, expand to sub-categories', (tester) async {
      await pumpPerson(tester);
      final food = find.text('Food & Daily Living');
      final shopping = find.text('Shopping & Lifestyle');
      expect(tester.getTopLeft(food.first).dy, lessThan(tester.getTopLeft(shopping).dy));
      expect(find.byKey(const Key('family-person-sub-Groceries')), findsNothing);
      await tester.tap(find.byKey(const Key('family-person-category-Food & Daily Living')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('family-person-sub-Groceries')), findsOneWidget);
      expect(find.byKey(const Key('family-person-sub-Restaurants')), findsOneWidget);
    });

    testWidgets('trend shows six bars, the selected month last', (tester) async {
      await pumpPerson(tester);
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups.length, 6);
      expect(chart.data.barGroups.last.barRods.single.toY, 42000);
      expect(chart.data.barGroups[4].barRods.single.toY, 30000);
    });

    testWidgets('biggest entries show the share and the split; they are not tappable', (tester) async {
      await pumpPerson(tester);
      expect(find.text('Market run'), findsOneWidget);
      expect(find.text(_en.familySpendingSharedWith(2)), findsOneWidget);
      expect(find.text(_en.familySpendingSharedWith(0)), findsNothing);
      expect(find.text(formatMoney(30000, Currency.mmk)), findsWidgets);
      expect(find.ancestor(of: find.text('Market run'), matching: find.byType(InkWell)), findsNothing);
    });

    testWidgets('added by line', (tester) async {
      await pumpPerson(tester);
      expect(find.text(_en.familySpendingAddedBy('Mum (6), Dad (2)')), findsOneWidget);
      expect(find.text('Added by Mum (6), Dad (2)'), findsOneWidget);
    });

    testWidgets('a load error shows retry, which loads again', (tester) async {
      final calls = await pumpPerson(tester, failFirst: ApiException('Could not load'));
      expect(find.text('Could not load'), findsOneWidget);
      await tester.tap(find.byKey(const Key('family-person-retry')));
      await tester.pumpAndSettle();
      expect(calls.length, 2);
      expect(find.text('Market run'), findsOneWidget);
    });

    testWidgets('tapping a row on the month screen opens that person', (tester) async {
      final personCalls = <(DateTime, String?, Currency?)>[];
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('my')],
        home: FamilySpendingScreen(
          loader: _Loader().call,
          personLoader: (month, {memberId, currency}) async {
            personCalls.add((month, memberId, currency));
            return person();
          },
          now: () => DateTime(2025, 4, 18),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('family-spending-row-mama')));
      await tester.pumpAndSettle();
      expect(find.byType(FamilyPersonSpendingScreen), findsOneWidget);
      expect(personCalls.single, (DateTime(2025, 4), 'mama', Currency.mmk));
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
      (l) => l.familySpendingByCategory,
      (l) => l.familySpendingTrend,
      (l) => l.familySpendingBiggest,
      (l) => l.familySpendingSharedWith(2),
      (l) => l.familySpendingAddedBy('Mum (6)'),
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
