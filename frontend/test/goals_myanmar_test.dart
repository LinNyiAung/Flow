import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/goals/goals_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGoals extends GoalProvider {
  _FakeGoals(this.fixed);
  final List<Goal> fixed;
  @override
  List<Goal> get goals => fixed;
  @override
  bool get isLoading => false;
  @override
  MultiCurrencyGoalsSummary? get multiCurrencySummary => MultiCurrencyGoalsSummary(
        totalGoals: 2,
        activeGoals: 2,
        achievedGoals: 0,
        currencySummaries: [
          CurrencySummary(
            currency: Currency.usd,
            activeGoals: 2,
            achievedGoals: 0,
            totalAllocated: 1500,
            totalTarget: 5800,
            overallProgress: 25.9,
          ),
        ],
      );
  @override
  Future<void> fetchGoals({GoalStatus? statusFilter, Currency? currency}) async {}
  @override
  Future<void> fetchSummary({Currency? currency}) async {}
  @override
  Future<void> fetchMultiCurrencySummary() async {}
}

class _FakeTransactions extends TransactionProvider {
  @override
  Future<void> fetchBalance({Currency? currency}) async {}
}

class _FakeNotifications extends NotificationProvider {
  @override
  Future<void> fetchUnreadCount() async {}
}

final _now = DateTime.now();
final _overdueDate = DateTime(_now.year, _now.month, _now.day - 4);

Goal _goal(String id, String name, {DateTime? targetDate}) => Goal(
      id: id,
      userId: 'u1',
      name: name,
      targetAmount: 2900,
      currentAmount: 750,
      targetDate: targetDate,
      goalType: GoalType.large_purchase,
      status: GoalStatus.active,
      progressPercentage: 25.9,
      createdAt: _now,
      updatedAt: _now,
      currency: Currency.usd,
    );

Future<void> _pump(WidgetTester tester, Locale locale) async {
  tester.view.physicalSize = const Size(360 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<GoalProvider>(
        create: (_) => _FakeGoals([
          _goal('g1', 'Laptop', targetDate: _overdueDate),
          _goal('g2', 'Motorbike'),
        ]),
      ),
      ChangeNotifierProvider<TransactionProvider>(create: (_) => _FakeTransactions()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => _FakeNotifications()),
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
      home: GoalsScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final my = AppLocalizations(const Locale('my'));

  testWidgets('English: goal type and hero read as before', (tester) async {
    await _pump(tester, const Locale('en'));
    expect(find.text('LARGE PURCHASE'), findsOneWidget);
    expect(find.text(r'of $5,800.00 · 2 Goals'), findsOneWidget);
    expect(find.text('Overdue · was due ${formatOverdueDueDate(_overdueDate)}'), findsOneWidget);
  });

  testWidgets('Myanmar 360: goal type, due date and hero are in Myanmar', (tester) async {
    await _pump(tester, const Locale('my'));
    expect(tester.takeException(), isNull);

    expect(find.text('LARGE PURCHASE'), findsNothing);
    expect(find.text(my.goalTypeLabel(GoalType.large_purchase)), findsOneWidget);
    expect(find.textContaining(RegExp(r'^of ')), findsNothing);
    expect(find.text('${my.ofAmount(r'$5,800.00')} · 2 ${my.goals}'), findsOneWidget);

    final overdue = find.text(my.goalOverdueWasDue(formatOverdueDueDate(_overdueDate, locale: 'my')));
    expect(overdue, findsOneWidget);
    expect(find.textContaining(RegExp(r'Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec')), findsNothing);
    // The overdue line wraps rather than ending in "…".
    expect(tester.renderObject<RenderParagraph>(overdue).didExceedMaxLines, isFalse);
  });

  testWidgets('Myanmar 360: every filter chip is on screen', (tester) async {
    await _pump(tester, const Locale('my'));
    for (final label in [my.filterChipAll, my.active, my.achieved]) {
      final rect = tester.getRect(find.widgetWithText(ChoiceChip, label));
      expect(rect.left, greaterThanOrEqualTo(0), reason: label);
      expect(rect.right, lessThanOrEqualTo(360), reason: label);
    }
  });
}
