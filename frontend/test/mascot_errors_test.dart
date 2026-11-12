import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart' show AuthWrapper;
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
import 'package:frontend/screens/budgets/ai_budget_suggestion_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/app_bar_title.dart';
import 'package:frontend/widgets/mascot.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoBudgets extends BudgetProvider {
  _NoBudgets({this.suggestionError});
  final String? suggestionError;
  @override
  List<Budget> get budgets => const [];
  @override
  bool get isLoading => false;
  @override
  String? get error => suggestionError;
  @override
  Future<void> fetchBudgets({bool activeOnly = false, BudgetPeriod? period, Currency? currency}) async {}
  @override
  Future<void> fetchMultiCurrencySummary() async {}
  @override
  Future<AIBudgetSuggestion?> getAISuggestions({
    required BudgetPeriod period,
    required DateTime startDate,
    DateTime? endDate,
    List<String>? includeCategories,
    int analysisMonths = 3,
    String? userContext,
    required Currency currency,
  }) async =>
      null;
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

/// A saved session that could not be restored: the server was unreachable.
class _Unreachable extends AuthProvider {
  @override
  bool get isAuthenticated => false;
  @override
  bool get sessionRestoreFailed => true;
  @override
  bool get isAuthChecking => false;
  @override
  String? get sessionRestoreError => AppLocalizations(const Locale('en')).errorNetworkUnreachable;
  @override
  Future<void> checkAuthStatus() async {}
}

Finder _pose(MascotPose pose) =>
    find.byWidgetPredicate((w) => w is Mascot && w.pose == pose, description: 'Mascot(${pose.name})');

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

AIBudgetSuggestionScreen _suggestion() => AIBudgetSuggestionScreen(
      period: BudgetPeriod.monthly,
      startDate: DateTime(2026, 11, 1),
      currency: Currency.mmk,
    );

void main() {
  final en = AppLocalizations(const Locale('en'));

  group('full-page errors', () {
    testWidgets('budget suggestion, server failure: oops_sad', (tester) async {
      await _pump(tester, _suggestion(), budgets: _NoBudgets(suggestionError: 'Failed to get budget ideas (500)'));
      _expectAbove(tester, MascotPose.oopsSad, en.failedToGenerateSuggestion);
      expect(find.text(en.tryAgain), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    });

    testWidgets('budget suggestion, no connection: offline_sad', (tester) async {
      await _pump(tester, _suggestion(), budgets: _NoBudgets(suggestionError: en.errorNetworkUnreachable));
      _expectAbove(tester, MascotPose.offlineSad, en.failedToGenerateSuggestion);
    });

    testWidgets('session restore, server unreachable: offline_sad', (tester) async {
      await _pump(tester, const AuthWrapper(), auth: _Unreachable());
      _expectAbove(tester, MascotPose.offlineSad, en.sessionRestoreFailedTitle);
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
      await tester.pumpWidget(const SizedBox()); // stops the auto-retry timer
    });

    testWidgets('Myanmar 360 px: "ကိုတိုးပွား၏ ဘတ်ဂျက် အကြံပြုချက်" title is never cut to "…"', (tester) async {
      final my = AppLocalizations(const Locale('my'));
      await _pump(tester, _suggestion(),
          lang: 'my', width: 360, budgets: _NoBudgets(suggestionError: 'Failed (500)'));
      expect(find.widgetWithText(AppBarTitle, my.aiBudgetSuggestion), findsOneWidget);
    });

    for (final lang in ['en', 'my']) {
      testWidgets('$lang 360 px: error screens do not overflow', (tester) async {
        await _pump(tester, _suggestion(),
            lang: lang, width: 360, height: 640, budgets: _NoBudgets(suggestionError: 'x' * 300));
        expect(tester.takeException(), isNull);
        await _pump(tester, const AuthWrapper(), lang: lang, width: 360, height: 640, auth: _Unreachable());
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
