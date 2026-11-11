import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/goals/goal_detail_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';

final _now = DateTime.now();

Goal _goal({DateTime? targetDate, double progress = 12.5}) => Goal(
      id: 'g1',
      userId: 'u1',
      name: 'Emergency fund',
      targetAmount: 8000,
      currentAmount: 1000,
      targetDate: targetDate,
      goalType: GoalType.savings,
      status: GoalStatus.active,
      progressPercentage: progress,
      createdAt: _now,
      updatedAt: _now,
      currency: Currency.usd,
    );

Future<void> _pump(WidgetTester tester, Goal goal) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => GoalProvider()),
      ChangeNotifierProvider(create: (_) => TransactionProvider()),
    ],
    child: MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: const [Locale('en'), Locale('my')],
      home: GoalDetailScreen(goal: goal),
    ),
  ));
  await tester.pump();
}

void main() {
  final l = AppLocalizations(const Locale('en'));

  testWidgets('overdue: badge and banner say so; the subtitle is just the category', (tester) async {
    await _pump(tester, _goal(targetDate: DateTime(_now.year, _now.month, _now.day - 4)));

    expect(find.text(l.goalOverdue.toUpperCase()), findsOneWidget); // badge
    expect(find.byKey(const ValueKey('goal-overdue-banner')), findsOneWidget);
    // "was due …" only in the banner.
    expect(find.textContaining('was due'), findsOneWidget);
    expect(find.text(l.goalTypeLabel(GoalType.savings).toUpperCase()), findsOneWidget);
  });

  testWidgets('not overdue: the subtitle keeps the due date', (tester) async {
    await _pump(tester, _goal(targetDate: DateTime(_now.year + 1, 1, 15)));
    expect(find.textContaining('${l.goalTypeLabel(GoalType.savings).toUpperCase()} · ${l.dueDatePrefix}'), findsOneWidget);
    expect(find.byKey(const ValueKey('goal-overdue-banner')), findsNothing);
  });

  testWidgets('progress is a whole percent, like the goals list', (tester) async {
    await _pump(tester, _goal(progress: 12.5));
    expect(find.text('13% ${l.completed}'), findsOneWidget);
    expect(find.textContaining('12.5%'), findsNothing);
  });

  test('progressLabel rounds to a whole percent', () {
    expect(_goal(progress: 12.5).progressLabel, '13%');
    expect(_goal(progress: 0.4).progressLabel, '0%');
    expect(_goal(progress: 100).progressLabel, '100%');
  });
}
