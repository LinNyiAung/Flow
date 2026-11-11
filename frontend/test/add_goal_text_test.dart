import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/goals/add_goal_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoBalanceFetch extends TransactionProvider {
  @override
  Future<void> fetchBalance({Currency? currency}) async {}
}

Future<void> _pump(WidgetTester tester, Locale locale) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<TransactionProvider>(create: (_) => _NoBalanceFetch()),
      ChangeNotifierProvider<GoalProvider>(create: (_) => GoalProvider()),
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
      home: AddGoalScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  // The initial-contribution field (with the wallet icon).
  final field = find.ancestor(
      of: find.byIcon(Icons.account_balance_wallet_rounded), matching: find.byType(TextFormField));
  await tester.enterText(field, '5');
  await tester.pumpAndSettle();
}

void main() {
  test('"left after this goal" in both languages', () {
    expect(AppLocalizations(const Locale('en')).leftAfterThisGoal(r'$5.00'), r'$5.00 left after this goal');
    final my = AppLocalizations(const Locale('my')).leftAfterThisGoal('K5');
    expect(my, contains('K5'));
    expect(my, isNot(contains('left')));
  });

  testWidgets('Myanmar: the line under Available for goals is in Myanmar', (tester) async {
    await _pump(tester, const Locale('my'));
    final my = AppLocalizations(const Locale('my'));
    expect(find.textContaining('left after this goal'), findsNothing);
    expect(find.text(my.leftAfterThisGoal(r'-$5.00')), findsOneWidget);
  });

  testWidgets('English keeps its wording', (tester) async {
    await _pump(tester, const Locale('en'));
    expect(find.text(r'-$5.00 left after this goal'), findsOneWidget);
  });
}
