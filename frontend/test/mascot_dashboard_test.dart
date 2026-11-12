import 'package:flutter/material.dart';
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
import 'package:frontend/widgets/ai_chat_fab.dart';
import 'package:frontend/widgets/mascot.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoTransactions extends TransactionProvider {
  @override
  List<Transaction> get transactions => const [];
  @override
  List<Transaction> get weekOutflows => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchTransactions({int? limit, int? skip, TransactionType? type, DateTime? startDate, DateTime? endDate, Currency? currency}) async {}
  @override
  Future<void> fetchWeekSpending({DateTime? today}) async {}
  @override
  Future<void> fetchBalance({Currency? currency}) async {}
}

class _NoBudgets extends BudgetProvider {
  @override
  List<Budget> get budgets => const [];
  @override
  List<Budget> get activeBudgets => const [];
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
  List<Goal> get activeGoals => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchGoals({GoalStatus? statusFilter, Currency? currency}) async {}
  @override
  Future<void> fetchSummary({Currency? currency}) async {}
  @override
  Future<void> fetchMultiCurrencySummary() async {}
}

class _NoChat extends ChatProvider {
  @override
  Future<void> loadChatHistory() async {}
}

class _FakeNotifications extends NotificationProvider {
  @override
  Future<void> fetchUnreadCount() async {}
}

Finder _pose(MascotPose pose) =>
    find.byWidgetPredicate((w) => w is Mascot && w.pose == pose, description: 'Mascot(${pose.name})');

Widget _app(Widget home, {String lang = 'en'}) => MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('my')],
      home: home,
    );

Future<void> _pumpHome(WidgetTester tester, {String lang = 'en', double width = 390}) async {
  tester.view.physicalSize = Size(width * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<TransactionProvider>(create: (_) => _NoTransactions()),
      ChangeNotifierProvider<BudgetProvider>(create: (_) => _NoBudgets()),
      ChangeNotifierProvider<GoalProvider>(create: (_) => _NoGoals()),
      ChangeNotifierProvider<ChatProvider>(create: (_) => _NoChat()),
      ChangeNotifierProvider<InsightProvider>(create: (_) => InsightProvider()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => _FakeNotifications()),
      ChangeNotifierProvider<PlanProvider>(create: (_) => PlanProvider()),
    ],
    child: _app(const HomeScreen(), lang: lang),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final en = AppLocalizations(const Locale('en'));

  testWidgets('chat card: his face and "Ask Ko Toe Pwar", not the old icon', (tester) async {
    await _pumpHome(tester);
    final card = find.ancestor(of: find.text(en.askAboutYourFinances), matching: find.byType(GestureDetector)).first;
    expect(find.descendant(of: card, matching: _pose(MascotPose.face)), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Ask Ko Toe Pwar')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byIcon(Icons.forum_rounded)), findsNothing);
  });

  testWidgets('empty Recent: quickadd_joy above the existing texts', (tester) async {
    await _pumpHome(tester);
    expect(_pose(MascotPose.quickaddJoy), findsOneWidget);
    expect(tester.getSize(_pose(MascotPose.quickaddJoy)).height, inInclusiveRange(110, 140));
    expect(find.text(en.noTransactions), findsOneWidget);
    expect(find.text(en.tapToAddFirst), findsOneWidget);
    expect(tester.getBottomLeft(_pose(MascotPose.quickaddJoy)).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text(en.noTransactions)).dy));
    expect(find.byIcon(Icons.receipt_long_rounded), findsNothing);
  });

  for (final lang in ['en', 'my']) {
    testWidgets('$lang 360: empty dashboard has no overflow', (tester) async {
      await _pumpHome(tester, lang: lang, width: 360);
      expect(tester.takeException(), isNull);
      expect(_pose(MascotPose.quickaddJoy), findsOneWidget);
    });
  }

  testWidgets('chat button: his face, named after him', (tester) async {
    await tester.pumpWidget(_app(const Scaffold(floatingActionButton: AiChatFab())));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AiChatFab), matching: _pose(MascotPose.face)), findsOneWidget);
    expect(find.text('Ask Ko Toe Pwar'), findsOneWidget);
    expect(find.byIcon(Icons.smart_toy), findsNothing);
    final fab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
    expect(fab.tooltip, 'Chat with Ko Toe Pwar');
  });
}
