import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/report.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/report/reports_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/money.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

FinancialReport _report({Currency currency = Currency.mmk}) => FinancialReport(
      period: ReportPeriod.month,
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 30, 23, 59, 59),
      totalInflow: 0,
      totalOutflow: 100000,
      netBalance: -100000,
      inflowByCategory: const [],
      outflowByCategory: const [],
      goals: const [],
      totalAllocatedToGoals: 0,
      totalTransactions: 4,
      inflowCount: 0,
      outflowCount: 4,
      averageDailyInflow: 0,
      averageDailyOutflow: 100000 / 30,
      generatedAt: DateTime(2026, 11, 11),
      currency: currency,
    );

FamilyBreakdown _breakdown(List<BreakdownRow> rows, {double total = 100000}) =>
    FamilyBreakdown(currency: Currency.mmk, totalSpent: total, rows: rows);

const _longName = 'ကိုမောင်မောင်လွင်လွင်ဘုန်းမြတ်ထွန်းထွန်းအောင်အောင်ကျော်ကျော်';

final _rows = [
  const BreakdownRow(memberId: 'm2', displayName: 'Daw Mya', amount: 40000),
  const BreakdownRow(memberId: null, displayName: 'Whole family', amount: 30000),
  const BreakdownRow(memberId: 'm3', displayName: 'Uncle Tun', status: 'former', amount: 20000),
  const BreakdownRow(memberId: 'm4', displayName: _longName, amount: 10000),
];

Future<void> _pump(
  WidgetTester tester, {
  required Locale locale,
  required BreakdownLoader loader,
  BookMode mode = BookMode.family,
  BookModeProvider? books,
  ThemeData? theme,
  ReportLoader? reportLoader,
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(360 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final bookProvider = books ?? BookModeProvider();
  if (books == null && mode == BookMode.family) await bookProvider.setMode(BookMode.family);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => PlanProvider(loader: () async => PlanStatus(plan: Plan.free))),
      ChangeNotifierProvider<BookModeProvider>.value(value: bookProvider),
    ],
    child: MaterialApp(
      theme: theme,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('my')],
      home: ReportsScreen(
        reportLoader: reportLoader ?? ({required period, startDate, endDate, currency}) async => _report(),
        breakdownLoader: loader,
      ),
    ),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<void> _few(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final my = AppLocalizations(const Locale('my'));
  final en = AppLocalizations(const Locale('en'));

  testWidgets('family mode: the card lists Whole family first, then the server order', (tester) async {
    final calls = <List<Object?>>[];
    await _pump(tester, locale: const Locale('en'), loader: ({required start, required end, required currency}) async {
      calls.add([start, end, currency]);
      return _breakdown(_rows);
    });
    expect(find.text(en.whoWeSpentOn), findsOneWidget);
    expect(calls, hasLength(1));
    expect(calls.single[2], Currency.mmk);
    expect((calls.single[0] as DateTime).day, 1);
    expect((calls.single[1] as DateTime).day, 30);

    final labels = [en.wholeFamily, 'Daw Mya', en.familyFormerName('Uncle Tun'), _longName];
    final tops = [for (final l in labels) tester.getTopLeft(find.text(l)).dy];
    expect(tops, orderedEquals([...tops]..sort()), reason: 'rows are out of order: $tops');
    expect(find.text(formatMoney(30000, Currency.mmk)), findsOneWidget);
    expect(find.text(formatMoney(40000, Currency.mmk)), findsOneWidget);
    expect(find.text(formatMoney(20000, Currency.mmk)), findsOneWidget);
    expect(find.text(en.familyFormerName('Uncle Tun')), findsOneWidget);
    // MMK is whole kyat: no decimals.
    expect(find.textContaining('.00'), findsNothing);
    // One share bar per row.
    final bars = tester.widgetList<LinearProgressIndicator>(find.descendant(
      of: find.byKey(const ValueKey('family-breakdown-card')),
      matching: find.byType(LinearProgressIndicator),
    ));
    expect(bars.map((b) => b.value), [0.3, 0.4, 0.2, 0.1]);
  });

  testWidgets('personal mode: no card and no request', (tester) async {
    var calls = 0;
    await _pump(tester, locale: const Locale('en'), mode: BookMode.personal,
        loader: ({required start, required end, required currency}) async {
      calls++;
      return _breakdown(_rows);
    });
    expect(find.text(en.whoWeSpentOn), findsNothing);
    expect(find.byKey(const ValueKey('family-breakdown-card')), findsNothing);
    expect(calls, 0);
  });

  testWidgets('empty period shows a short text', (tester) async {
    await _pump(tester, locale: const Locale('en'),
        loader: ({required start, required end, required currency}) async => _breakdown(const [], total: 0));
    expect(find.text(en.whoWeSpentOn), findsOneWidget);
    expect(find.text(en.noFamilySpending), findsOneWidget);
  });

  testWidgets('error shows the server message', (tester) async {
    await _pump(tester, locale: const Locale('en'),
        loader: ({required start, required end, required currency}) async => throw Exception('Boom from server'));
    expect(find.text('Boom from server'), findsOneWidget);
  });

  testWidgets('loading shows a progress indicator in the card', (tester) async {
    final c = Completer<FamilyBreakdown>();
    await _pump(tester, locale: const Locale('en'), settle: false,
        loader: ({required start, required end, required currency}) => c.future);
    expect(find.descendant(
      of: find.byKey(const ValueKey('family-breakdown-card')),
      matching: find.byType(CircularProgressIndicator),
    ), findsOneWidget);
    c.complete(_breakdown(_rows));
    await tester.pumpAndSettle();
    expect(find.text('Daw Mya'), findsOneWidget);
  });

  testWidgets('a late response for an old period is ignored', (tester) async {
    final first = Completer<FamilyBreakdown>();
    final second = Completer<FamilyBreakdown>();
    final pending = [first, second];
    var n = 0;
    await _pump(tester, locale: const Locale('en'), settle: false, loader: ({required start, required end, required currency}) {
      return pending[n++].future;
    });
    // Switch the period (Week) while the first load is still pending.
    await tester.tap(find.text(en.week));
    await _few(tester);
    second.complete(_breakdown(const [BreakdownRow(memberId: 'm9', displayName: 'Second', amount: 5)], total: 5));
    await _few(tester);
    expect(find.text('Second'), findsOneWidget);
    first.complete(_breakdown(const [BreakdownRow(memberId: 'm8', displayName: 'Stale', amount: 5)], total: 5));
    await _few(tester);
    expect(find.text('Stale'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('Myanmar 360: long names wrap, no overflow', (tester) async {
    await _pump(tester, locale: const Locale('my'),
        loader: ({required start, required end, required currency}) async => _breakdown(_rows));
    expect(tester.takeException(), isNull);
    expect(find.text(my.whoWeSpentOn), findsOneWidget);
    expect(find.text(my.wholeFamily), findsOneWidget);
    for (final p in tester.renderObjectList<RenderParagraph>(find.text(_longName))) {
      expect(p.didExceedMaxLines, isFalse);
      expect(p.size.width, lessThanOrEqualTo(360));
    }
    expect(find.text(my.familyFormerName('Uncle Tun')), findsOneWidget);
  });

  testWidgets('Myanmar 360 dark: no overflow', (tester) async {
    await _pump(tester, locale: const Locale('my'), theme: ThemeData.dark(),
        loader: ({required start, required end, required currency}) async => _breakdown(_rows));
    expect(tester.takeException(), isNull);
    expect(find.text(my.whoWeSpentOn), findsOneWidget);
  });
}
