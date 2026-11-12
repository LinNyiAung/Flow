import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/notification.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/app_version_provider.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/budget_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/budgets/budgets_screen.dart';
import 'package:frontend/screens/goals/goals_screen.dart';
import 'package:frontend/screens/notifications/notifications_screen.dart';
import 'package:frontend/screens/transactions/transactions_list_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/mascot.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoBudgets extends BudgetProvider {
  @override
  List<Budget> get budgets => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchBudgets({bool activeOnly = false, BudgetPeriod? period, Currency? currency}) async {}
  @override
  Future<void> fetchMultiCurrencySummary() async {}
}

class _NoGoals extends GoalProvider {
  @override
  List<Goal> get goals => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchGoals({GoalStatus? statusFilter, Currency? currency}) async {}
  @override
  Future<void> fetchSummary({Currency? currency}) async {}
  @override
  Future<void> fetchMultiCurrencySummary() async {}
}

class _Transactions extends TransactionProvider {
  @override
  Future<void> fetchBalance({Currency? currency}) async {}
}

class _NoNotifications extends NotificationProvider {
  @override
  List<AppNotification> get notifications => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchNotifications({bool unreadOnly = false}) async {}
  @override
  Future<void> fetchUnreadCount() async {}
}

Finder _pose(MascotPose pose) =>
    find.byWidgetPredicate((w) => w is Mascot && w.pose == pose, description: 'Mascot(${pose.name})');

Finder get _anyMascot => find.byType(Mascot);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  String lang = 'en',
  double width = 390,
  double height = 900,
  BudgetProvider? budgets,
  AuthProvider? auth,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => auth ?? AuthProvider()),
      ChangeNotifierProvider<AppVersionProvider>(create: (_) => AppVersionProvider()),
      ChangeNotifierProvider<BudgetProvider>(create: (_) => budgets ?? _NoBudgets()),
      ChangeNotifierProvider<GoalProvider>(create: (_) => _NoGoals()),
      ChangeNotifierProvider<TransactionProvider>(create: (_) => _Transactions()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => _NoNotifications()),
      ChangeNotifierProvider<PlanProvider>(create: (_) => PlanProvider()),
    ],
    child: MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('my')],
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
}

/// [pose] is drawn 110-140 px tall, above [text].
void _expectAbove(WidgetTester tester, MascotPose pose, String text) {
  expect(_pose(pose), findsOneWidget);
  expect(tester.getSize(_pose(pose)).height, inInclusiveRange(110, 140));
  expect(find.text(text), findsOneWidget);
  expect(tester.getBottomLeft(_pose(pose)).dy, lessThanOrEqualTo(tester.getTopLeft(find.text(text)).dy));
}

void main() {
  final en = AppLocalizations(const Locale('en'));

  group('empty states', () {
    testWidgets('Transactions, no filter: quickadd_joy', (tester) async {
      await _pump(tester, TransactionsListScreen());
      _expectAbove(tester, MascotPose.quickaddJoy, en.noTransactions);
      expect(find.text(en.tapToAddFirst), findsOneWidget);
    });

    testWidgets('Transactions, a filter on: no mascot', (tester) async {
      await _pump(tester, TransactionsListScreen(initialCurrency: Currency.usd));
      expect(find.text(en.emptyStateTitle), findsOneWidget);
      expect(_anyMascot, findsNothing);
    });

    testWidgets('Budgets, none: budgetpie_happy', (tester) async {
      await _pump(tester, BudgetsScreen());
      // "No budgets yet" is also the hero's line; the empty state's is the last.
      expect(_pose(MascotPose.budgetpieHappy), findsOneWidget);
      expect(tester.getSize(_pose(MascotPose.budgetpieHappy)).height, inInclusiveRange(110, 140));
      expect(find.text(en.createYourFirstBudget), findsOneWidget);
      expect(tester.getBottomLeft(_pose(MascotPose.budgetpieHappy)).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.text(en.createYourFirstBudget)).dy));
      expect(find.byIcon(Icons.savings_rounded), findsNothing);
    });

    testWidgets('Goals, none: goal_joy', (tester) async {
      await _pump(tester, GoalsScreen());
      _expectAbove(tester, MascotPose.goalJoy, en.noGoalsYet);
      expect(find.text(en.createGoalGetStarted), findsOneWidget);
    });

    testWidgets('Goals, "Achieved" filter with none: no mascot', (tester) async {
      await _pump(tester, GoalsScreen());
      await tester.tap(find.text(en.achieved).first);
      await tester.pumpAndSettle();
      expect(find.text(en.noGoalsYet), findsOneWidget);
      expect(_anyMascot, findsNothing);
    });

    testWidgets('Notifications, none: mail_happy instead of the bell tile', (tester) async {
      await _pump(tester, NotificationsScreen());
      _expectAbove(tester, MascotPose.mailHappy, en.noNotificationsYet);
      expect(find.text(en.notifyGoalsProgress), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
    });

    for (final lang in ['en', 'my']) {
      testWidgets('$lang 360 px: empty screens do not overflow', (tester) async {
        for (final screen in <Widget>[TransactionsListScreen(), BudgetsScreen(), GoalsScreen(), NotificationsScreen()]) {
          await _pump(tester, screen, lang: lang, width: 360, height: 640);
          expect(tester.takeException(), isNull, reason: '${screen.runtimeType}');
          expect(_anyMascot, findsOneWidget, reason: '${screen.runtimeType}');
        }
      });
    }
  });
}
