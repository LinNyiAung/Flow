import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/report.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/report/reports_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The month report as the backend sends it: Nov 1 00:00 – Nov 30 23:59:59,
/// averages divided by the 30 days.
FinancialReport _novemberReport() => FinancialReport(
      period: ReportPeriod.month,
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 30, 23, 59, 59),
      totalInflow: 3840,
      totalOutflow: 387.25,
      netBalance: 3452.75,
      inflowByCategory: const [],
      outflowByCategory: const [],
      goals: const [],
      totalAllocatedToGoals: 0,
      totalTransactions: 12,
      inflowCount: 2,
      outflowCount: 10,
      averageDailyInflow: 3840 / 30,
      averageDailyOutflow: 387.25 / 30,
      generatedAt: DateTime(2026, 11, 11),
      currency: Currency.usd,
    );

void main() {
  group('inclusiveCalendarDays', () {
    test('a whole month counts every day', () {
      expect(inclusiveCalendarDays(DateTime(2026, 11, 1), DateTime(2026, 11, 30, 23, 59, 59)), 30);
      expect(inclusiveCalendarDays(DateTime(2026, 2, 1), DateTime(2026, 2, 28, 23, 59, 59)), 28);
      expect(inclusiveCalendarDays(DateTime(2026, 12, 1), DateTime(2026, 12, 31, 23, 59, 59)), 31);
    });

    test('a single day is one day', () {
      expect(inclusiveCalendarDays(DateTime(2026, 11, 11), DateTime(2026, 11, 11, 23, 59, 59)), 1);
      expect(inclusiveCalendarDays(DateTime(2026, 11, 11), DateTime(2026, 11, 11)), 1);
    });

    test('a week is seven days', () {
      expect(inclusiveCalendarDays(DateTime(2026, 11, 9), DateTime(2026, 11, 15, 23, 59, 59)), 7);
    });

    test('a range across a DST change still counts calendar days', () {
      // March 2026 has the EU/US clock change; local midnights are 23 h apart once.
      expect(inclusiveCalendarDays(DateTime(2026, 3, 1), DateTime(2026, 3, 31, 23, 59, 59)), 31);
    });

    test('the report getter uses it', () {
      expect(_novemberReport().daysCovered, 30);
    });
  });

  testWidgets('Days covered is 30 and Per day shows the Average Daily Expenses figure', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PlanProvider(loader: () async => PlanStatus(plan: Plan.free))),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('my')],
          home: ReportsScreen(
            reportLoader: ({required period, startDate, endDate, currency}) async => _novemberReport(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Days covered.
    final daysCard = find.ancestor(of: find.text('Days covered'), matching: find.byType(Card)).first;
    expect(find.descendant(of: daysCard, matching: find.text('30')), findsOneWidget);

    // "Per day" tile shows exactly the Average Daily Expenses value.
    final perDayTile = find.ancestor(of: find.text('Per day'), matching: find.byType(Column)).first;
    final perDay = tester
        .widgetList<Text>(find.descendant(of: perDayTile, matching: find.byType(Text)))
        .map((t) => t.data)
        .firstWhere((s) => s != null && s.startsWith(r'$'));
    final avgRow = find.ancestor(of: find.text('Average Daily Expenses'), matching: find.byType(Row)).first;
    final avg = tester
        .widgetList<Text>(find.descendant(of: avgRow, matching: find.byType(Text)))
        .map((t) => t.data)
        .firstWhere((s) => s != null && s.startsWith(r'$'));
    expect(perDay, avg);
    expect(avg, r'$12.91'); // 387.25 / 30
    expect(find.text(r'$128.00'), findsOneWidget); // income: 3,840 / 30
    expect(tester.takeException(), isNull);
  });
}
