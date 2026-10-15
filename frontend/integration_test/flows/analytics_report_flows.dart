import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/charts/inflow_analytics_screen.dart';
import 'package:frontend/screens/charts/outflow_analytics_screen.dart';
import 'package:frontend/screens/report/reports_screen.dart';

import '../support/accounts.dart';
import '../support/harness.dart';

Future<void> pickTodayInDialog() async {
  await waitFor(find.byType(DatePickerDialog));
  await tap(find.text('OK'));
}

/// Custom period: tap both "Select" date cards and accept the default.
Future<void> pickCustomRange() async {
  step('custom range');
  for (var i = 0; i < 2; i++) {
    final sel = find.text(L.select);
    if (!await waitFor(sel, timeout: const Duration(seconds: 5), orNull: true)) break;
    await tap(sel.first);
    await pickTodayInDialog();
    await settle(1500);
  }
}

Future<void> analyticsTour(Type screen, String drawerLabel, {required bool pie}) async {
  await drawerGo(drawerLabel);
  await waitFor(find.byType(screen));
  final r = await waitAny([find.byType(BarChart), find.text(L.noDataAvailable)], timeout: const Duration(seconds: 30));
  check(r == 0, '$drawerLabel: no bar chart rendered for the rich account (got ${r == 1 ? 'no-data' : 'timeout'})');
  if (pie) check(find.byType(PieChart).evaluate().isNotEmpty, '$drawerLabel: pie chart missing');
  for (final p in [L.daily, L.yearly, L.monthly]) {
    step('$drawerLabel period $p');
    await tap(find.text(p).first);
    await settle(1500);
    check(find.byType(BarChart).evaluate().isNotEmpty || hasText(L.noDataAvailable),
        '$drawerLabel: nothing rendered for period $p');
  }
  step('$drawerLabel currency MMK');
  await tap(find.byIcon(Icons.expand_more_rounded).first);
  await tap(find.textContaining('MMK · ').last);
  await waitAny([find.byType(BarChart), find.text(L.noDataAvailable)], timeout: const Duration(seconds: 30));
  await settle(1000);
  check(hasTextContaining('K'), '$drawerLabel: MMK totals not shown after currency switch');
  step('$drawerLabel currency THB');
  await tap(find.byIcon(Icons.expand_more_rounded).first);
  await tap(find.textContaining('THB · ').last);
  await waitAny([find.byType(BarChart), find.text(L.noDataAvailable)], timeout: const Duration(seconds: 30));
  step('$drawerLabel custom');
  await tap(find.text(L.custom).first);
  await settle(800);
  await pickCustomRange();
  await waitAny([find.byType(BarChart), find.text(L.noDataAvailable)], timeout: const Duration(seconds: 30));
  await settle(1000);
  step('$drawerLabel scroll');
  await scrollTo(find.text('__never__'), maxSwipes: 4);
}

void analyticsFlows() {
  group('07 Analytics', () {
    e2eTest('analytics: outflow screen periods/currency/charts', (t) async {
      await login(premium);
      await analyticsTour(OutflowAnalyticsScreen, L.outflowAnalytics, pie: true);
    });
    e2eTest('analytics: inflow screen periods/currency/charts', (t) async {
      await login(premium);
      await analyticsTour(InflowAnalyticsScreen, L.inflowAnalytics, pie: false);
    });
  });
}

Future<int> _waitReport() => waitAny([
      find.text(L.netBalance),
      find.textContaining('Net · '),
      find.text(L.errorTitle),
      find.text(L.selectDatesToGenerateReport),
    ], timeout: const Duration(seconds: 60));

void reportFlows() {
  group('08 Reports', () {
    e2eTest('reports: week/month/year/custom, multi + single currency, PDF', (t) async {
      await login(premium);
      await drawerGo(L.financialReports);
      await waitFor(find.byType(ReportsScreen));
      var r = await _waitReport();
      check(r == 0 || r == 1, 'Reports: initial report did not render (state $r)');
      for (final p in [L.week, L.month, L.year]) {
        step('period $p');
        await tap(find.text(p).first);
        r = await _waitReport();
        check(r == 0 || r == 1, 'Reports: $p report did not render (state $r: ${visibleTexts().take(12).join(' | ')})');
        await settle(800);
      }
      step('custom');
      await tap(find.text(L.custom).first);
      await settle(800);
      await pickCustomRange();
      r = await _waitReport();
      check(r == 0 || r == 1, 'Reports: custom report did not render (state $r)');
      step('single currency USD');
      await tap(find.text(L.month).first);
      await _waitReport();
      await settle(800);
      final chip = find.text(L.allCurrencies);
      if (await waitFor(chip, timeout: const Duration(seconds: 5), orNull: true)) {
        await tap(chip.first);
        await tap(find.textContaining('USD · ').last);
      }
      r = await _waitReport();
      await settle(1500);
      check(hasTextContaining('Net · '), 'Reports: single-currency (USD) report did not render');
      step('scroll report');
      await scrollTo(find.text(L.expensesByCategory), maxSwipes: 10);
      await scrollTo(find.text(L.financialReports), dy: 600, maxSwipes: 10);
      step('download PDF');
      final share = find.byIcon(Icons.ios_share_rounded);
      if (!await waitFor(share, timeout: const Duration(seconds: 5), orNull: true)) {
        appBug('Reports: no download/export action for a single-currency report');
        return;
      }
      await tap(share);
      await tap(find.text('PDF'));
      final d = await waitAny([find.text(L.reportDownloadedSuccessfully), find.textContaining(L.errorDownloadReport)],
          timeout: const Duration(seconds: 90));
      check(d == 0, 'PDF download (premium) did not succeed: ${d == 1 ? visibleTexts().firstWhere((x) => x.contains(L.errorDownloadReport), orElse: () => '') : 'timeout'}');
    });

    e2eTest('reports: free user PDF download → premium gate', (t) async {
      await login(free);
      await drawerGo(L.financialReports);
      await waitFor(find.byType(ReportsScreen));
      await _waitReport();
      final chip = find.text(L.allCurrencies);
      if (await waitFor(chip, timeout: const Duration(seconds: 8), orNull: true)) {
        await tap(chip.first);
        await tap(find.textContaining('USD · ').last);
      }
      await _waitReport();
      await settle(1000);
      final share = find.byIcon(Icons.ios_share_rounded);
      if (!await waitFor(share, timeout: const Duration(seconds: 8), orNull: true)) {
        // Hidden for free users counts as a gate.
        return;
      }
      step('free user taps PDF');
      await tap(share);
      await tap(find.text('PDF'));
      final d = await waitAny([
        find.text(L.reportDownloadedSuccessfully),
        find.textContaining(L.errorDownloadReport),
        find.textContaining('remium'),
      ], timeout: const Duration(seconds: 60));
      final shown = visibleTexts().where((x) => x.contains(L.errorDownloadReport) || x.contains('remium')).join(' | ');
      // ignore: avoid_print
      print('E2E_INFO|free PDF outcome=$d|$shown');
      check(d != 0, 'Free user could download the PDF report (no premium gate)');
      if (d == 1) {
        check(!shown.contains('Exception:'),
            'Free-user PDF error shows a raw "Exception:" string instead of a premium paywall: $shown');
      }
    });
  });
}
