import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/notification.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/app_version_provider.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/budget_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/budgets/budget_detail_screen.dart';
import 'package:frontend/screens/budgets/budgets_screen.dart';
import 'package:frontend/screens/budgets/create_budget_screen.dart';
import 'package:frontend/screens/goals/goal_detail_screen.dart';
import 'package:frontend/screens/goals/goals_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/family_permissions.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// HTTP: ONE MockClient for the file (ApiService binds its inner client once).
// ---------------------------------------------------------------------------

late Future<http.Response> Function(http.Request) _respond;
final List<http.Request> _requests = [];
final _mock = MockClient((request) {
  _requests.add(request);
  return _respond(request);
});

http.Response _json(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

// ---------------------------------------------------------------------------
// Data and fakes.
// ---------------------------------------------------------------------------

FamilyOverview _overview({String role = FamilyMember.roleMember, bool readOnly = false}) => FamilyOverview(
      family: Family(id: 'f', name: 'Aung family', readOnly: readOnly),
      myMemberId: 'm1',
      myRole: role,
      members: [FamilyMember(id: 'm1', displayName: 'Dad', kind: 'account', role: role, isMe: true)],
    );

class _Family extends FamilyProvider {
  _Family([FamilyOverview overview = FamilyOverview.none]) {
    debugApply(overview);
  }
  @override
  Future<void> refresh() async {}
}

Future<BookModeProvider> _books(BookMode mode) async {
  final books = BookModeProvider();
  await books.setMode(mode);
  return books;
}

final _day = DateTime(2026, 11, 1);

Budget _budget() => Budget(
      id: 'b1',
      bookId: 'u1',
      name: 'Groceries',
      period: BudgetPeriod.monthly,
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 30, 23, 59),
      categoryBudgets: const [],
      totalBudget: 100,
      totalSpent: 20,
      remainingBudget: 80,
      percentageUsed: 20,
      status: BudgetStatus.active,
      isActive: true,
      createdAt: _day,
      updatedAt: _day,
      currency: Currency.usd,
    );

Goal _goal({double current = 50, DateTime? targetDate, GoalStatus status = GoalStatus.active}) => Goal(
      id: 'g1',
      bookId: 'u1',
      name: 'Holiday',
      targetAmount: 200,
      currentAmount: current,
      targetDate: targetDate,
      goalType: GoalType.savings,
      status: status,
      progressPercentage: 25,
      createdAt: _day,
      updatedAt: _day,
      currency: Currency.usd,
    );

class _Budgets extends BudgetProvider {
  _Budgets(this._list);
  final List<Budget> _list;
  int refreshes = 0;
  @override
  List<Budget> get budgets => _list;
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchBudgets({bool activeOnly = false, BudgetPeriod? period, Currency? currency}) async {}
  @override
  Future<void> fetchMultiCurrencySummary() async {}
  @override
  Future<void> refreshBudget(String budgetId) async => refreshes++;
  @override
  Future<Budget?> getBudget(String budgetId) async => _list.isEmpty ? null : _list.first;
}

class _Goals extends GoalProvider {
  _Goals(this._list);
  final List<Goal> _list;
  @override
  List<Goal> get goals => _list;
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchGoals({GoalStatus? statusFilter, Currency? currency}) async {}
  @override
  Future<void> fetchSummary({Currency? currency}) async {}
  @override
  Future<void> fetchMultiCurrencySummary() async {}
  @override
  Future<Goal?> getGoal(String goalId) async => _list.isEmpty ? null : _list.first;
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

final _en = AppLocalizations(const Locale('en'));

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  FamilyProvider? family,
  BookModeProvider? books,
  BudgetProvider? budgets,
  GoalProvider? goals,
  String lang = 'en',
  double width = 390,
  double height = 900,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<AppVersionProvider>(create: (_) => AppVersionProvider()),
      ChangeNotifierProvider<BudgetProvider>.value(value: budgets ?? _Budgets([_budget()])),
      ChangeNotifierProvider<GoalProvider>.value(value: goals ?? _Goals([_goal()])),
      ChangeNotifierProvider<TransactionProvider>(create: (_) => _Transactions()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => _NoNotifications()),
      ChangeNotifierProvider<PlanProvider>(create: (_) => PlanProvider()),
      if (family != null) ChangeNotifierProvider<FamilyProvider>.value(value: family),
      if (books != null) ChangeNotifierProvider<BookModeProvider>.value(value: books),
    ],
    child: MaterialApp(
      locale: Locale(lang),
      themeMode: themeMode,
      theme: ThemeData(useMaterial3: true),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
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

/// A person's setup: [mode] (personal or family) and their [role].
Future<void> _pumpAs(
  WidgetTester tester,
  Widget home, {
  required BookMode mode,
  String role = FamilyMember.roleMember,
  bool readOnly = false,
  BudgetProvider? budgets,
  GoalProvider? goals,
  String lang = 'en',
  double width = 390,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await _pump(
    tester,
    home,
    family: _Family(_overview(role: role, readOnly: readOnly)),
    books: await _books(mode),
    budgets: budgets,
    goals: goals,
    lang: lang,
    width: width,
    themeMode: themeMode,
  );
}

Finder get _fab => find.byType(FloatingActionButton);
Finder get _edit => find.byIcon(Icons.edit_rounded);
Finder get _delete => find.byIcon(Icons.delete_rounded);
Finder get _note => find.byKey(const ValueKey('family-admins-only-note'));

/// Taps [finder] after scrolling it into view (the goal screen's money
/// button sits below its History card).
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
    _requests.clear();
    _respond = (_) async => _json({});
    // Every call (the goal screen's history too) goes to the fake server.
    ApiService.httpClientOverride = _mock;
    ApiService.bookMode = BookMode.personal;
    ApiService.onNoFamily = null;
  });
  tearDown(() {
    ApiService.httpClientOverride = null;
    ApiService.bookMode = BookMode.personal;
    ApiService.onNoFamily = null;
  });

  group('the helpers', () {
    Future<(bool, bool)> ask(WidgetTester tester, BookMode mode, String role, {bool readOnly = false, bool noProviders = false}) async {
      late bool manage;
      late bool add;
      final builder = Builder(builder: (context) {
        manage = canManageBudgetsGoals(context);
        add = canAddToGoal(context);
        return const SizedBox();
      });
      if (noProviders) {
        await tester.pumpWidget(builder);
      } else {
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<FamilyProvider>.value(value: _Family(_overview(role: role, readOnly: readOnly))),
            ChangeNotifierProvider<BookModeProvider>.value(value: await _books(mode)),
          ],
          child: builder,
        ));
      }
      return (manage, add);
    }

    testWidgets('Personal: both true, whatever the role', (tester) async {
      expect(await ask(tester, BookMode.personal, FamilyMember.roleMember), (true, true));
      expect(await ask(tester, BookMode.personal, FamilyMember.roleMember, readOnly: true), (true, true));
    });

    testWidgets('no family providers at all: both true', (tester) async {
      expect(await ask(tester, BookMode.personal, 'x', noProviders: true), (true, true));
    });

    testWidgets('Family: admins and the owner manage; a member only adds', (tester) async {
      expect(await ask(tester, BookMode.family, FamilyMember.roleOwner), (true, true));
      expect(await ask(tester, BookMode.family, FamilyMember.roleAdmin), (true, true));
      expect(await ask(tester, BookMode.family, FamilyMember.roleMember), (false, true));
    });

    testWidgets('Family read-only: nobody manages or adds', (tester) async {
      expect(await ask(tester, BookMode.family, FamilyMember.roleOwner, readOnly: true), (false, false));
      expect(await ask(tester, BookMode.family, FamilyMember.roleMember, readOnly: true), (false, false));
    });
  });

  group('Budgets screen', () {
    testWidgets('Personal: the create button shows, no note', (tester) async {
      await _pumpAs(tester, BudgetsScreen(), mode: BookMode.personal);
      expect(_fab, findsOneWidget);
      expect(_note, findsNothing);
    });

    testWidgets('Family member: no create button, an admins-only line', (tester) async {
      await _pumpAs(tester, BudgetsScreen(), mode: BookMode.family);
      expect(_fab, findsNothing);
      expect(_note, findsOneWidget);
      expect(find.text(_en.onlyAdminsChangeFamilyBudgets), findsOneWidget);
      // Everyone still sees the budget.
      expect(find.text('Groceries'), findsOneWidget);
    });

    testWidgets('Family admin and owner: the create button shows', (tester) async {
      for (final role in [FamilyMember.roleAdmin, FamilyMember.roleOwner]) {
        await _pumpAs(tester, BudgetsScreen(), mode: BookMode.family, role: role);
        expect(_fab, findsOneWidget, reason: role);
        expect(_note, findsNothing, reason: role);
      }
    });

    testWidgets('Family read-only: no create button, the read-only banner', (tester) async {
      await _pumpAs(tester, BudgetsScreen(), mode: BookMode.family, role: FamilyMember.roleOwner, readOnly: true);
      expect(_fab, findsNothing);
      expect(find.text(_en.familyReadOnlyBanner), findsOneWidget);
    });

    testWidgets('a member with no budgets is not told to create one', (tester) async {
      await _pumpAs(tester, BudgetsScreen(), mode: BookMode.family, budgets: _Budgets([]));
      expect(find.text(_en.createYourFirstBudget), findsNothing);
    });
  });

  group('Budget detail', () {
    testWidgets('Personal: edit and delete show, and it refreshes the budget', (tester) async {
      final budgets = _Budgets([_budget()]);
      await _pumpAs(tester, BudgetDetailScreen(budget: _budget()), mode: BookMode.personal, budgets: budgets);
      expect(_edit, findsOneWidget);
      expect(_delete, findsOneWidget);
      expect(budgets.refreshes, 1);
    });

    testWidgets('Family member: no edit or delete, and no refresh request', (tester) async {
      final budgets = _Budgets([_budget()]);
      await _pumpAs(tester, BudgetDetailScreen(budget: _budget()), mode: BookMode.family, budgets: budgets);
      expect(_edit, findsNothing);
      expect(_delete, findsNothing);
      expect(budgets.refreshes, 0);
      expect(find.text('Groceries'), findsWidgets);
    });

    testWidgets('Family admin: edit, delete and the refresh', (tester) async {
      final budgets = _Budgets([_budget()]);
      await _pumpAs(tester, BudgetDetailScreen(budget: _budget()), mode: BookMode.family, role: FamilyMember.roleAdmin, budgets: budgets);
      expect(_edit, findsOneWidget);
      expect(_delete, findsOneWidget);
      expect(budgets.refreshes, 1);
    });

    testWidgets('Family read-only: even the owner has no edit, delete or refresh', (tester) async {
      final budgets = _Budgets([_budget()]);
      await _pumpAs(tester, BudgetDetailScreen(budget: _budget()),
          mode: BookMode.family, role: FamilyMember.roleOwner, readOnly: true, budgets: budgets);
      expect(_edit, findsNothing);
      expect(_delete, findsNothing);
      expect(budgets.refreshes, 0);
    });
  });

  group('Create budget: the AI suggestion', () {
    testWidgets('Personal: the AI entry shows', (tester) async {
      await _pumpAs(tester, CreateBudgetScreen(), mode: BookMode.personal);
      expect(find.text(_en.generateAiBudget), findsOneWidget);
    });

    testWidgets('Family admin: the AI entry shows', (tester) async {
      await _pumpAs(tester, CreateBudgetScreen(), mode: BookMode.family, role: FamilyMember.roleAdmin);
      expect(find.text(_en.generateAiBudget), findsOneWidget);
    });

    testWidgets('Family member (a stale screen): no AI entry', (tester) async {
      await _pumpAs(tester, CreateBudgetScreen(), mode: BookMode.family);
      expect(find.text(_en.generateAiBudget), findsNothing);
    });
  });

  group('Goals screen', () {
    testWidgets('Personal: the create button and "Manage Funds" show', (tester) async {
      await _pumpAs(tester, GoalsScreen(), mode: BookMode.personal);
      expect(_fab, findsOneWidget);
      expect(find.text(_en.manageFunds), findsOneWidget);
      expect(_note, findsNothing);
    });

    testWidgets('Family member: no create button, "Add money" instead of "Manage Funds"', (tester) async {
      await _pumpAs(tester, GoalsScreen(), mode: BookMode.family);
      expect(_fab, findsNothing);
      expect(find.text(_en.onlyAdminsChangeFamilyGoals), findsOneWidget);
      expect(find.text(_en.addMoney), findsOneWidget);
      expect(find.text(_en.manageFunds), findsNothing);
    });

    testWidgets('Family admin: the create button and "Manage Funds"', (tester) async {
      await _pumpAs(tester, GoalsScreen(), mode: BookMode.family, role: FamilyMember.roleAdmin);
      expect(_fab, findsOneWidget);
      expect(find.text(_en.manageFunds), findsOneWidget);
    });

    testWidgets('Family read-only: no create button, no money button, the banner', (tester) async {
      await _pumpAs(tester, GoalsScreen(), mode: BookMode.family, role: FamilyMember.roleOwner, readOnly: true);
      expect(_fab, findsNothing);
      expect(find.text(_en.manageFunds), findsNothing);
      expect(find.text(_en.addMoney), findsNothing);
      expect(find.text(_en.familyReadOnlyBanner), findsOneWidget);
    });

    testWidgets('a member with no goals is not told to create one', (tester) async {
      await _pumpAs(tester, GoalsScreen(), mode: BookMode.family, goals: _Goals([]));
      expect(find.text(_en.createGoalGetStarted), findsNothing);
    });
  });

  group('Goal detail', () {
    final overdue = DateTime(2020, 1, 1);

    testWidgets('Personal: edit, delete, Manage Funds with Add and Withdraw', (tester) async {
      await _pumpAs(tester, GoalDetailScreen(goal: _goal()), mode: BookMode.personal);
      expect(_edit, findsOneWidget);
      expect(_delete, findsOneWidget);
      await _tapVisible(tester, find.text(_en.manageFunds));
      expect(find.text(_en.add), findsWidgets);
      expect(find.text(_en.withdraw), findsWidgets);
    });

    testWidgets('Family member: no edit or delete; Add money opens an add-only sheet', (tester) async {
      await _pumpAs(tester, GoalDetailScreen(goal: _goal()), mode: BookMode.family);
      expect(_edit, findsNothing);
      expect(_delete, findsNothing);
      expect(find.text(_en.manageFunds), findsNothing);
      await _tapVisible(tester, find.text(_en.addMoney));
      expect(find.text(_en.withdraw), findsNothing);
      expect(find.widgetWithText(ElevatedButton, _en.add), findsOneWidget);
    });

    testWidgets('Family member: Add money shows even when the goal holds nothing', (tester) async {
      await _pumpAs(tester, GoalDetailScreen(goal: _goal(current: 0)), mode: BookMode.family);
      expect(find.text(_en.addMoney), findsOneWidget);
    });

    testWidgets('Family member: an overdue goal has no "Extend date" (it is an edit)', (tester) async {
      await _pumpAs(tester, GoalDetailScreen(goal: _goal(targetDate: overdue)), mode: BookMode.family);
      expect(find.byKey(const ValueKey('goal-overdue-banner')), findsOneWidget);
      expect(find.text(_en.goalExtendDate), findsNothing);
    });

    testWidgets('Family admin: edit, delete, and Add and Withdraw', (tester) async {
      await _pumpAs(tester, GoalDetailScreen(goal: _goal()), mode: BookMode.family, role: FamilyMember.roleAdmin);
      expect(_edit, findsOneWidget);
      expect(_delete, findsOneWidget);
      await _tapVisible(tester, find.text(_en.manageFunds));
      expect(find.text(_en.withdraw), findsWidgets);
    });

    testWidgets('Family read-only: nothing to press, the banner says why', (tester) async {
      await _pumpAs(tester, GoalDetailScreen(goal: _goal(targetDate: overdue)),
          mode: BookMode.family, role: FamilyMember.roleOwner, readOnly: true);
      expect(_edit, findsNothing);
      expect(_delete, findsNothing);
      expect(find.text(_en.manageFunds), findsNothing);
      expect(find.text(_en.addMoney), findsNothing);
      expect(find.text(_en.goalExtendDate), findsNothing);
      expect(find.text(_en.familyReadOnlyBanner), findsOneWidget);
    });
  });

  group('errors the server still sends', () {
    http.Response refusal(int status, String code, String message) => _json({
          'detail': {'code': code, 'message': message}
        }, status);

    Future<T> run<T>(Future<T> Function() call) => http.runWithClient(call, () => _mock);

    test('a refused change keeps the server message and is not "reported"', () async {
      ApiService.bookMode = BookMode.family;
      _respond = (_) async => refusal(403, 'not_allowed', 'Only family admins can do that.');
      final goals = GoalProvider();
      expect(await run(() => goals.deleteGoal('g1')), isFalse);
      expect(goals.error, contains('Only family admins can do that.'));
      expect(goals.errorReported, isFalse);
      final budgets = BudgetProvider();
      expect(await run(() => budgets.deleteBudget('b1')), isFalse);
      expect(budgets.error, contains('Only family admins can do that.'));
      expect(budgets.errorReported, isFalse);
    });

    test('a no_family the app already reported is flagged, and a later success clears it', () async {
      ApiService.bookMode = BookMode.family;
      ApiService.onNoFamily = () {};
      _respond = (_) async => refusal(409, 'no_family', "You're not in a family.");
      final goals = GoalProvider();
      expect(await run(() => goals.contributeToGoal(goalId: 'g1', amount: 5)), isFalse);
      expect(goals.errorReported, isTrue);
      final budgets = BudgetProvider();
      expect(await run(() => budgets.deleteBudget('b1')), isFalse);
      expect(budgets.errorReported, isTrue);
      // The next call starts clean.
      _respond = (_) async => _json({});
      budgets.clearError();
      expect(budgets.errorReported, isFalse);
    });
  });

  group('layout at 360 px in Myanmar', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('member and read-only screens do not overflow ($mode)', (tester) async {
        final screens = <Widget Function()>[
          () => BudgetsScreen(),
          () => GoalsScreen(),
          () => BudgetDetailScreen(budget: _budget()),
          () => GoalDetailScreen(goal: _goal(targetDate: DateTime(2020, 1, 1))),
        ];
        for (final readOnly in [false, true]) {
          for (final build in screens) {
            await _pumpAs(tester, build(),
                mode: BookMode.family, readOnly: readOnly, lang: 'my', width: 360, themeMode: mode);
            expect(tester.takeException(), isNull);
          }
        }
      });
    }

    testWidgets('the add-only sheet fits', (tester) async {
      await _pumpAs(tester, GoalDetailScreen(goal: _goal()), mode: BookMode.family, lang: 'my', width: 360);
      final button = find.text(AppLocalizations(const Locale('my')).addMoney);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget, reason: 'the sheet opened');
      expect(tester.takeException(), isNull);
    });
  });
}
