import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/screens/charts/inflow_analytics_screen.dart';
import 'package:frontend/screens/charts/outflow_analytics_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotifications extends NotificationProvider {
  @override
  Future<void> fetchUnreadCount() async {}
}

final _now = DateTime.now();
final _thisMonth = DateTime(_now.year, _now.month, 1, 12);
final _lastMonth = DateTime(_now.year, _now.month - 1, 1, 12);

Transaction _tx(TransactionType type, String category, double amount, DateTime date) => Transaction(
      id: '$category-$amount-${date.month}',
      userId: 'u1',
      type: type,
      mainCategory: category,
      subCategory: 'Other',
      date: date,
      amount: amount,
      currency: Currency.usd,
      createdAt: date,
      updatedAt: date,
    );

/// Six spending categories; the busiest month totals 1,940.
final _outflows = [
  _tx(TransactionType.outflow, 'Housing & Utilities', 900, _thisMonth),
  _tx(TransactionType.outflow, 'Food & Daily Living', 500, _thisMonth),
  _tx(TransactionType.outflow, 'Transportation', 240, _thisMonth),
  _tx(TransactionType.outflow, 'Health & Personal Care', 150, _thisMonth),
  _tx(TransactionType.outflow, 'Entertainment & Leisure', 100, _thisMonth),
  _tx(TransactionType.outflow, 'Education', 50, _thisMonth),
  _tx(TransactionType.outflow, 'Food & Daily Living', 1000, _lastMonth),
];

/// The busiest month's income is 4,610.
final _inflows = [
  _tx(TransactionType.inflow, 'Employment Income', 4600, _thisMonth),
  _tx(TransactionType.inflow, 'Gifts Received', 10, _thisMonth),
  _tx(TransactionType.inflow, 'Employment Income', 3000, _lastMonth),
];

Future<List<Transaction>> _loader({
  int limit = 50,
  int skip = 0,
  TransactionType? type,
  DateTime? startDate,
  DateTime? endDate,
  Currency? currency,
}) async =>
    [..._outflows, ..._inflows].where((t) => type == null || t.type == type).toList();

Future<void> _pump(WidgetTester tester, Widget screen, {required Locale locale, double width = 360}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => _FakeNotifications()),
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
      home: screen,
    ),
  ));
  await tester.pumpAndSettle();
}

/// Period pills in one row, and the currency menu fully on screen.
void _expectTidyPeriodRow(WidgetTester tester, AppLocalizations l, double width) {
  final tops = [l.daily, l.monthly, l.yearly, l.custom].map((s) => tester.getTopLeft(find.text(s)).dy).toSet();
  expect(tops, hasLength(1), reason: 'period buttons are not on one row');
  final currency = tester.getRect(
    find.ancestor(of: find.byIcon(Icons.currency_exchange_rounded), matching: find.byType(InkWell)).first,
  );
  expect(currency.left, greaterThanOrEqualTo(0));
  expect(currency.right, lessThanOrEqualTo(width));
}

void main() {
  final my = AppLocalizations(const Locale('my'));
  final en = AppLocalizations(const Locale('en'));

  group('Outflow analytics', () {
    testWidgets('Myanmar 360: legend names in full, under the donut', (tester) async {
      await _pump(tester, const OutflowAnalyticsScreen(transactionLoader: _loader), locale: const Locale('my'));
      expect(tester.takeException(), isNull);
      final donut = tester.getRect(find.byType(PieChart));
      for (final name in ['Housing & Utilities', 'Food & Daily Living', 'Entertainment & Leisure']) {
        final f = find.text(name);
        expect(tester.renderObject<RenderParagraph>(f).didExceedMaxLines, isFalse, reason: '$name is cut off');
        expect(tester.getTopLeft(f).dy, greaterThan(donut.bottom), reason: 'legend is not under the donut');
      }
    });

    testWidgets('English 390: legend beside the donut', (tester) async {
      await _pump(tester, const OutflowAnalyticsScreen(transactionLoader: _loader), locale: const Locale('en'), width: 390);
      final donut = tester.getRect(find.byType(PieChart));
      expect(tester.getTopLeft(find.text('Housing & Utilities')).dx, greaterThan(donut.right));
    });

    testWidgets('slices use distinct categorical colours, matched by the legend', (tester) async {
      await _pump(tester, const OutflowAnalyticsScreen(transactionLoader: _loader), locale: const Locale('en'), width: 390);
      final sections = tester.widget<PieChart>(find.byType(PieChart)).data.sections;
      final colors = sections.map((s) => s.color).toList();
      expect(colors, AppTheme.chartCategorical.take(6).toList());
      final swatches = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.constraints == const BoxConstraints.tightFor(width: 10, height: 10))
          .map((c) => (c.decoration as BoxDecoration).color)
          .toList();
      expect(swatches, colors);
    });

    testWidgets('Spending by Month has a round top and even labels', (tester) async {
      await _pump(tester, const OutflowAnalyticsScreen(transactionLoader: _loader), locale: const Locale('en'), width: 390);
      final data = tester.widget<BarChart>(find.byType(BarChart)).data;
      expect(data.maxY, 2500);
      expect(data.titlesData.leftTitles.sideTitles.interval, 500);
      expect(data.gridData.horizontalInterval, 500);
    });

    testWidgets('period buttons stay one row; currency menu on screen (EN 390, MY 360)', (tester) async {
      await _pump(tester, const OutflowAnalyticsScreen(transactionLoader: _loader), locale: const Locale('en'), width: 390);
      _expectTidyPeriodRow(tester, en, 390);
      await _pump(tester, const OutflowAnalyticsScreen(transactionLoader: _loader), locale: const Locale('my'));
      _expectTidyPeriodRow(tester, my, 360);
    });
  });

  group('Inflow analytics', () {
    testWidgets('Myanmar 360: entry counts in Myanmar, names in full', (tester) async {
      await _pump(tester, const InflowAnalyticsScreen(transactionLoader: _loader), locale: const Locale('my'));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('entr'), findsNothing);
      expect(find.text(my.entriesCount(1)), findsOneWidget);
      expect(find.text(my.entriesCount(2)), findsOneWidget);
      final name = find.text('Employment Income');
      expect(tester.renderObject<RenderParagraph>(name).didExceedMaxLines, isFalse);
    });

    testWidgets('Income by Month has a round top and even labels', (tester) async {
      await _pump(tester, const InflowAnalyticsScreen(transactionLoader: _loader), locale: const Locale('en'), width: 390);
      final data = tester.widget<BarChart>(find.byType(BarChart)).data;
      expect(data.maxY, 6000);
      expect(data.titlesData.leftTitles.sideTitles.interval, 2000);
    });

    testWidgets('period buttons stay one row; currency menu on screen (EN 390, MY 360)', (tester) async {
      await _pump(tester, const InflowAnalyticsScreen(transactionLoader: _loader), locale: const Locale('en'), width: 390);
      _expectTidyPeriodRow(tester, en, 390);
      await _pump(tester, const InflowAnalyticsScreen(transactionLoader: _loader), locale: const Locale('my'));
      _expectTidyPeriodRow(tester, my, 360);
    });
  });
}
