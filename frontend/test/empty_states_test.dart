import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/budget_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/budgets/budgets_screen.dart';
import 'package:frontend/screens/transactions/transactions_list_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/hero_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No budgets and no summary; never touches the network.
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

class _FakeNotifications extends NotificationProvider {
  @override
  Future<void> fetchUnreadCount() async {}
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<BudgetProvider>(create: (_) => _NoBudgets()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => _FakeNotifications()),
      ChangeNotifierProvider<PlanProvider>(create: (_) => PlanProvider()),
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
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l = AppLocalizations(const Locale('en'));

  testWidgets('Budgets with no budgets: no bare "0"; "No budgets yet" is the main line', (tester) async {
    await _pump(tester, BudgetsScreen());
    final hero = find.byType(HeroCard);
    final line = find.descendant(of: hero, matching: find.text(l.noBudgetsYet));
    expect(line, findsOneWidget);
    expect(tester.widget<Text>(line).style?.fontSize, greaterThanOrEqualTo(20), reason: 'not the main line');
    // The three stat tiles still read 0; there is no fourth, big "0".
    expect(find.descendant(of: hero, matching: find.text('0')), findsNWidgets(3));
  });

  // No server in tests: the list loads empty.
  testWidgets('Transactions with no filter: "No transactions yet" and the + hint', (tester) async {
    await _pump(tester, TransactionsListScreen());
    expect(find.text(l.noTransactions), findsOneWidget);
    expect(find.text(l.tapToAddFirst), findsOneWidget);
    expect(find.text(l.emptyStateTitle), findsNothing);
    expect(find.text(l.emptyStateSubtitle), findsNothing);
  });

  testWidgets('Transactions with a filter on keep the filter wording', (tester) async {
    await _pump(tester, TransactionsListScreen(initialCurrency: Currency.usd));
    expect(find.text(l.emptyStateTitle), findsOneWidget);
    expect(find.text(l.emptyStateSubtitle), findsOneWidget);
    expect(find.text(l.noTransactions), findsNothing);
  });
}
