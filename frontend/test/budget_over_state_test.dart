import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/budget_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/screens/budgets/budget_detail_screen.dart';
import 'package:frontend/screens/budgets/budgets_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serves a fixed list and never touches the network.
class _FakeBudgetProvider extends BudgetProvider {
  final List<Budget> fixed;
  _FakeBudgetProvider(this.fixed);

  @override
  List<Budget> get budgets => fixed;
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchBudgets({bool activeOnly = false, BudgetPeriod? period, Currency? currency}) async {}
  @override
  Future<void> fetchMultiCurrencySummary() async {}
  @override
  Future<void> refreshBudget(String budgetId) async {}
  @override
  Future<Budget?> getBudget(String budgetId) async => null;
}

CategoryBudget _cat(String name, double cap, double spent) => CategoryBudget(
      mainCategory: name,
      allocatedAmount: cap,
      spentAmount: spent,
      percentageUsed: spent / cap * 100,
      isExceeded: spent > cap,
    );

Budget _budget(double total, List<CategoryBudget> cats) {
  final now = DateTime.now();
  final spent = cats.fold<double>(0, (s, c) => s + c.spentAmount);
  return Budget(
    id: 'b1',
    userId: 'u1',
    name: 'November',
    period: BudgetPeriod.monthly,
    startDate: DateTime(now.year, now.month, 1),
    endDate: DateTime(now.year, now.month + 1, 0, 23, 59),
    categoryBudgets: cats,
    totalBudget: total,
    totalSpent: spent,
    remainingBudget: total - spent,
    percentageUsed: spent / total * 100,
    status: BudgetStatus.exceeded,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    currency: Currency.usd,
  );
}

/// Total $1,500, 16% used; Entertainment is $46.84 over its $60 cap.
Budget _oneCategoryOver() => _budget(1500, [
      _cat('Food & Dining', 500, 133.30),
      _cat('Entertainment & Leisure', 60, 106.84),
      _cat('Transportation', 300, 0.72),
    ]);

/// Total within cap, but Entertainment and Transportation are over.
Budget _twoCategoriesOver() => _budget(1500, [
      _cat('Food & Dining', 500, 133.30),
      _cat('Entertainment & Leisure', 60, 106.84),
      _cat('Transportation', 30, 50),
    ]);

/// The total itself is $40 over.
Budget _totalOver() => _budget(200, [
      _cat('Food & Dining', 150, 140),
      _cat('Entertainment & Leisure', 50, 100),
    ]);

Widget _app(Widget home, List<Budget> budgets) => MultiProvider(
      providers: [
        ChangeNotifierProvider<BudgetProvider>(create: (_) => _FakeBudgetProvider(budgets)),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('my')],
        home: home,
      ),
    );

Future<void> _pumpList(WidgetTester tester, Budget budget) async {
  tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(BudgetsScreen(), [budget]));
  await tester.pumpAndSettle();
}

Future<void> _pumpDetail(WidgetTester tester, Budget budget) async {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(BudgetDetailScreen(budget: budget), [budget]));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('total over', () {
    testWidgets('list card keeps EXCEEDED and says how much over', (tester) async {
      await _pumpList(tester, _totalOver());
      expect(find.text('EXCEEDED'), findsOneWidget);
      expect(find.textContaining('CATEGOR'), findsNothing);
      expect(find.text(r'Over by $40.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail keeps the Budget Exceeded banner', (tester) async {
      await _pumpDetail(tester, _totalOver());
      expect(find.text('Budget Exceeded'), findsOneWidget);
      expect(find.textContaining('over its cap'), findsNothing);
      expect(find.textContaining('over their caps'), findsNothing);
      // Hero and the over category say "Over by", not a negative Remaining.
      expect(find.text(r'Over by $40.00'), findsOneWidget);
      expect(find.text(r'Over by $50.00'), findsOneWidget);
      expect(find.textContaining(r'$-'), findsNothing);
    });
  });

  group('one category over', () {
    testWidgets('list card says 1 CATEGORY OVER, still in red', (tester) async {
      await _pumpList(tester, _oneCategoryOver());
      expect(find.text('EXCEEDED'), findsNothing);
      final badge = find.text('1 CATEGORY OVER');
      expect(badge, findsOneWidget);
      final scheme = Theme.of(tester.element(badge)).colorScheme;
      expect(tester.widget<Text>(badge).style!.color, scheme.error);
      expect(find.text(r'Remaining $1,259.14'), findsOneWidget);
    });

    testWidgets('detail banner names the category; the row says Over by', (tester) async {
      await _pumpDetail(tester, _oneCategoryOver());
      expect(find.text('Budget Exceeded'), findsNothing);
      expect(find.text('A category is over its cap'), findsOneWidget);
      expect(find.textContaining('Entertainment & Leisure is over its cap.'), findsOneWidget);
      expect(find.textContaining('Food & Dining is over'), findsNothing);
      expect(find.text(r'Over by $46.84'), findsOneWidget);
      expect(find.textContaining(r'$-46.84'), findsNothing);
      expect(find.text(r'Remaining: $1,259.14'), findsOneWidget);
    });
  });

  group('two categories over', () {
    testWidgets('list card says 2 CATEGORIES OVER', (tester) async {
      await _pumpList(tester, _twoCategoriesOver());
      expect(find.text('EXCEEDED'), findsNothing);
      expect(find.text('2 CATEGORIES OVER'), findsOneWidget);
    });

    testWidgets('detail banner names both categories', (tester) async {
      await _pumpDetail(tester, _twoCategoriesOver());
      expect(find.text('Budget Exceeded'), findsNothing);
      expect(find.text('2 categories are over their caps'), findsOneWidget);
      expect(
        find.textContaining('Entertainment & Leisure, Transportation are over their caps.'),
        findsOneWidget,
      );
      expect(find.text(r'Over by $46.84'), findsOneWidget);
      expect(find.text(r'Over by $20.00'), findsOneWidget);
    });
  });

  testWidgets('Myanmar: one category over at 360 px fits', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<BudgetProvider>(create: (_) => _FakeBudgetProvider([_oneCategoryOver()])),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        locale: const Locale('my'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('my')],
        home: BudgetsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final badge = find.text('အမျိုးအစား 1 ခု ကျော်');
    expect(badge, findsOneWidget);
    final rect = tester.getRect(badge);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
  });
}
