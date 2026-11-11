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

/// Monthly, 85% used: the "approaching the limit" state.
Budget _nearLimit() {
  final now = DateTime.now();
  return Budget(
    id: 'b1',
    userId: 'u1',
    name: 'Monthly essentials',
    period: BudgetPeriod.monthly,
    startDate: DateTime(now.year, now.month, 1),
    endDate: DateTime(now.year, now.month + 1, 0, 23, 59),
    categoryBudgets: [
      CategoryBudget(
        mainCategory: 'Food & Dining',
        allocatedAmount: 1000,
        spentAmount: 850,
        percentageUsed: 85,
        isExceeded: false,
      ),
    ],
    totalBudget: 1000,
    totalSpent: 850,
    remainingBudget: 150,
    percentageUsed: 85,
    status: BudgetStatus.active,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    currency: Currency.usd,
  );
}

Widget _app(Widget home, List<Budget> budgets) => MultiProvider(
      providers: [
        ChangeNotifierProvider<BudgetProvider>(create: (_) => _FakeBudgetProvider(budgets)),
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
        home: home,
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final my = AppLocalizations(const Locale('my'));

  testWidgets('Budgets list: Over tile and period label are in Myanmar', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(BudgetsScreen(), [_nearLimit()]));
    await tester.pumpAndSettle();

    expect(find.text('Over'), findsNothing);
    expect(find.text(my.overShort), findsOneWidget);
    expect(find.textContaining('MONTHLY'), findsNothing);
    expect(find.text('${my.monthly} · USD'), findsOneWidget);
  });

  testWidgets('Budget detail: of, days, banner and status are in Myanmar', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final budget = _nearLimit();
    await tester.pumpWidget(_app(BudgetDetailScreen(budget: budget), [budget]));
    await tester.pumpAndSettle();

    expect(find.textContaining(RegExp(r'^of ')), findsNothing);
    expect(find.text(my.ofAmount(r'$1,000.00')), findsOneWidget);
    expect(find.textContaining("You've used"), findsNothing);
    expect(find.text(my.approachingBudgetBody('85')), findsOneWidget);
    expect(find.textContaining(RegExp(r'\d days')), findsNothing);
    expect(find.textContaining('ACTIVE'), findsNothing);
    expect(find.text(my.activeCap), findsOneWidget);
    expect(find.textContaining('MONTHLY'), findsNothing);
  });

  test('every new batch-B key has an English and a Myanmar text', () {
    final en = AppLocalizations(const Locale('en'));
    const keys = [
      'overShort', 'ofAmount', 'amountOfTotal', 'daysCount', 'daysAgoCount', 'approachingBudgetBody',
      'againstCurrentCap', 'netLabel', 'savedLabel', 'entriesLabel', 'perDayLabel', 'daysCoveredLabel',
      'oneEntry', 'entriesCount', 'weekdayInitials', 'goalTypeSavings', 'goalTypeDebtReduction',
      'goalTypeLargePurchase', 'goalTypeSavingsHint', 'goalTypeDebtReductionHint', 'goalTypeLargePurchaseHint',
      'continueChatting', 'askAboutYourFinances', 'heldForGoals', 'nothingHeld',
    ];
    for (final k in keys) {
      expect(en.translate(k), isNot(k), reason: 'EN $k');
      expect(my.translate(k), isNot(k), reason: 'MY $k');
      expect(my.translate(k), isNot(en.translate(k)), reason: 'MY $k is still English');
    }
    expect(my.translate('weekdayInitials').split(','), hasLength(7));
    expect(en.translate('weekdayInitials').split(','), hasLength(7));
  });
}
