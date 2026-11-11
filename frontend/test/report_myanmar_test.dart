import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

Future<void> _pump(WidgetTester tester, Locale locale) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(360 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => PlanProvider(loader: () async => PlanStatus(plan: Plan.free))),
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
      home: ReportsScreen(
        reportLoader: ({required period, startDate, endDate, currency}) async => _novemberReport(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final my = AppLocalizations(const Locale('my'));

  testWidgets('English: hero labels read as before', (tester) async {
    await _pump(tester, const Locale('en'));
    expect(find.text('Net · 1 Nov – 30 Nov 2026'), findsOneWidget);
    for (final label in ['Saved', 'Entries', 'Per day', 'Days covered']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('Myanmar 360: hero labels are in Myanmar and shown in full', (tester) async {
    await _pump(tester, const Locale('my'));
    expect(tester.takeException(), isNull);
    for (final label in ['Net', 'Saved', 'Entries', 'Per day', 'Days covered']) {
      expect(find.textContaining(label), findsNothing, reason: label);
    }
    expect(find.textContaining('Nov'), findsNothing);
    expect(find.textContaining(my.netLabel), findsWidgets);
    for (final label in [my.savedLabel, my.entriesLabel, my.perDayLabel]) {
      final f = find.text(label);
      expect(f, findsOneWidget, reason: label);
      expect(tester.renderObject<RenderParagraph>(f).didExceedMaxLines, isFalse, reason: '$label is cut off');
    }
    expect(find.text(my.daysCoveredLabel), findsOneWidget);
  });
}
