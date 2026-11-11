import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/budget_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/insight_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTransactions extends TransactionProvider {
  _FakeTransactions(this.fixed);
  final List<Transaction> fixed;
  @override
  List<Transaction> get transactions => fixed;
  @override
  List<Transaction> get weekOutflows => const [];
  @override
  Balance? get balance => Balance(
        currency: Currency.mmk,
        balance: 2500000,
        availableBalance: 2000000,
        allocatedToGoals: 500000,
        totalInflow: 3000000,
        totalOutflow: 500000,
      );
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchTransactions({int? limit, int? skip, TransactionType? type, DateTime? startDate, DateTime? endDate, Currency? currency}) async {}
  @override
  Future<void> fetchWeekSpending({DateTime? today}) async {}
  @override
  Future<void> fetchBalance({Currency? currency}) async {}
}

class _FakeBudgets extends BudgetProvider {
  _FakeBudgets(this.fixed);
  final List<Budget> fixed;
  @override
  List<Budget> get budgets => fixed;
  @override
  List<Budget> get activeBudgets => fixed;
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchBudgets({bool activeOnly = false, BudgetPeriod? period, Currency? currency}) async {}
  @override
  Future<void> fetchMultiCurrencySummary() async {}
}

class _FakeGoals extends GoalProvider {
  _FakeGoals(this.fixed);
  final List<Goal> fixed;
  @override
  List<Goal> get goals => fixed;
  @override
  List<Goal> get activeGoals => fixed;
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchGoals({GoalStatus? statusFilter, Currency? currency}) async {}
  @override
  Future<void> fetchSummary({Currency? currency}) async {}
  @override
  Future<void> fetchMultiCurrencySummary() async {}
}

class _FakeChat extends ChatProvider {
  @override
  Future<void> loadChatHistory() async {}
}

class _FakeNotifications extends NotificationProvider {
  @override
  Future<void> fetchUnreadCount() async {}
}

Budget _budget() {
  final now = DateTime.now();
  return Budget(
    id: 'b1',
    userId: 'u1',
    name: 'Monthly essentials',
    period: BudgetPeriod.monthly,
    startDate: DateTime(now.year, now.month, 1),
    endDate: DateTime(now.year, now.month, now.day + 19, 23, 59),
    categoryBudgets: [],
    totalBudget: 1500,
    totalSpent: 188.5,
    remainingBudget: 1311.5,
    percentageUsed: 12.6,
    status: BudgetStatus.active,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    currency: Currency.usd,
  );
}

Goal _goal() {
  final now = DateTime.now();
  return Goal(
    id: 'g1',
    userId: 'u1',
    name: 'New laptop',
    targetAmount: 5800,
    currentAmount: 1200,
    goalType: GoalType.large_purchase,
    status: GoalStatus.active,
    progressPercentage: 20.7,
    createdAt: now,
    updatedAt: now,
    currency: Currency.usd,
  );
}

Transaction _salary() {
  final now = DateTime.now();
  return Transaction(
    id: 't1',
    userId: 'u1',
    type: TransactionType.inflow,
    mainCategory: 'Employment Income',
    subCategory: 'Salary',
    date: now,
    amount: 1800000,
    currency: Currency.mmk,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pumpHome(WidgetTester tester, {required Locale locale, double width = 360}) async {
  tester.view.physicalSize = Size(width * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<TransactionProvider>(create: (_) => _FakeTransactions([_salary()])),
      ChangeNotifierProvider<BudgetProvider>(create: (_) => _FakeBudgets([_budget()])),
      ChangeNotifierProvider<GoalProvider>(create: (_) => _FakeGoals([_goal()])),
      ChangeNotifierProvider<ChatProvider>(create: (_) => _FakeChat()),
      ChangeNotifierProvider<InsightProvider>(create: (_) => InsightProvider()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => _FakeNotifications()),
      ChangeNotifierProvider<PlanProvider>(create: (_) => PlanProvider()),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('my')],
      home: const HomeScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The text is laid out in full: not cut short with an ellipsis.
void _expectShownInFull(WidgetTester tester, Finder text, {double screenWidth = 360}) {
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(paragraph.didExceedMaxLines, isFalse, reason: 'text is truncated');
  final rect = tester.getRect(text);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(screenWidth));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final my = AppLocalizations(const Locale('my'));

  testWidgets('English: preview lines read as before', (tester) async {
    await _pumpHome(tester, locale: const Locale('en'), width: 390);
    expect(find.text(r'$188.50 of $1,500.00 · 19 days remaining'), findsOneWidget);
    expect(find.text(r'$1,200.00 of $5,800.00'), findsOneWidget);
    expect(find.text('Ask me anything about your finances.'), findsOneWidget);
  });

  testWidgets('Myanmar 360: dashboard previews have no English left', (tester) async {
    await _pumpHome(tester, locale: const Locale('my'));
    expect(tester.takeException(), isNull);

    expect(find.textContaining(' of '), findsNothing);
    expect(find.textContaining('days remaining'), findsNothing);
    expect(
      find.text('${my.amountOfTotal(r'$188.50', r'$1,500.00')} · ${my.daysRemainingCount(19)}'),
      findsOneWidget,
    );
    expect(find.text(my.amountOfTotal(r'$1,200.00', r'$5,800.00')), findsOneWidget);
    expect(find.text(my.askAboutYourFinances), findsOneWidget);
    expect(find.textContaining('Ask me anything'), findsNothing);
  });

  testWidgets('Myanmar 360: a recent amount is shown in full', (tester) async {
    await _pumpHome(tester, locale: const Locale('my'));
    _expectShownInFull(tester, find.text('+K1,800,000'));
  });

  testWidgets('Myanmar 360: quick link labels are shown in full', (tester) async {
    await _pumpHome(tester, locale: const Locale('my'));
    for (final label in [my.inflowAnalytics, my.outflowAnalytics, my.financialReports]) {
      _expectShownInFull(tester, find.text(label));
    }
  });
}
