import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/settings/currency_settings_screen.dart';

import '../support/accounts.dart';
import '../support/harness.dart';

/// Text of the hero "Available to spend" value (e.g. "$1,234.00").
String? heroValue() {
  final label = find.text(L.availableToSpend);
  if (label.evaluate().isEmpty) return null;
  for (final t in visibleTexts()) {
    if (RegExp(r'^-?[\$K฿]-?[\d,]+\.\d\d$').hasMatch(t)) return t;
  }
  return null;
}

/// Changes the default currency through Settings → Currency.
Future<void> setDefaultCurrency(String displayName) async {
  step('settings → currency → $displayName');
  await drawerGo(L.settings);
  await tap(find.text(L.currency).first);
  await waitFor(find.byType(CurrencySettingsScreen));
  await tap(find.text(displayName));
  await settle(1500);
  await goHome();
  await settle(2000);
}

void homeFlows() {
  group('02 Home', () {
    e2eTest('home: balance card, currency switch, recent, pace, bell', (t) async {
      await login(premium);
      step('hero values');
      await expectSoon(find.text(L.availableToSpend), 'Home: "Available to spend" hero missing');
      final v = heroValue();
      check(v != null && v.startsWith(r'$'), 'Home hero value is not a USD amount: $v');
      check(hasText(L.inflow) && hasText(L.outflow), 'Home: inflow/outflow stat tiles missing');
      check(hasText('USD'), 'Home hero: USD currency pill missing');

      step('bell unread count');
      final token = await apiToken(premium);
      final unread = ((await apiGet(token, '/api/notifications/unread-count')) as Map)['unread_count'] as int;
      final expected = unread > 9 ? '9+' : '$unread';
      final badge = find.descendant(of: find.byType(AppBar), matching: find.text(expected));
      check(badge.evaluate().isNotEmpty,
          'Home bell badge does not show the unread count ($expected) — visible: ${visibleTexts().take(6)}');

      step('spending pace + recent');
      check(hasText(L.spendingPace), 'Home: Spending pace card missing');
      await scrollTo(find.text(L.recentTransactions));
      check(hasText(L.recentTransactions), 'Home: Recent header missing');
      check(!hasText(L.noTransactions), 'Home: Recent list empty for the rich premium account');

      step('scroll whole home (budgets/goals/shortcuts)');
      await scrollTo(find.text(L.financialReports), maxSwipes: 12);
      check(hasText(L.inflowAnalytics) && hasText(L.outflowAnalytics),
          'Home: analytics shortcuts missing at the bottom');
      await scrollTo(find.text(L.availableToSpend), dy: 400, maxSwipes: 12);

      step('multi-currency sheet');
      await tap(find.text('USD').first);
      await expectSoon(find.text(L.allCurrencyBalances), 'Home: tapping the currency pill did not open All Currency Balances');
      check(hasText('Myanmar Kyat (MMK)') && hasText('Thai Baht (THB)'),
          'All Currency Balances sheet does not list MMK and THB');
      await back();

      for (final c in [('Myanmar Kyat (MMK)', 'MMK', 'K'), ('Thai Baht (THB)', 'THB', '฿'), ('US Dollar (USD)', 'USD', r'$')]) {
        await setDefaultCurrency(c.$1);
        step('home shows ${c.$2}');
        await waitFor(find.byType(HomeScreen));
        final ok = await waitFor(find.text(c.$2), timeout: const Duration(seconds: 8), orNull: true);
        final hv = heroValue();
        final inCurrency = ok && hv != null && hv.replaceFirst('-', '').startsWith(c.$3);
        if (!inCurrency) {
          step('pull to refresh');
          await t.fling(find.byType(CustomScrollView).first, const Offset(0, 400), 1200);
          await settle(3500);
          final hv2 = heroValue();
          final fixed = hasText(c.$2) && hv2 != null && hv2.replaceFirst('-', '').startsWith(c.$3);
          appBug('Home keeps showing the old currency after changing the default currency to ${c.$2} '
              '(hero "$hv"); ${fixed ? 'only a pull-to-refresh updates it' : 'still wrong after pull-to-refresh ("$hv2")'}');
        }
      }
    });

    e2eTest('home: empty account shows empty states', (t) async {
      await login(empty);
      final v = heroValue();
      check(v == r'$0.00', 'Home (empty account): hero value should be \$0.00, got $v');
      step('empty recent');
      await scrollTo(find.text(L.noTransactions), maxSwipes: 4);
      check(hasText(L.noTransactions), 'Home (empty account): no "No transactions yet" empty state');
      step('empty screens');
      await drawerGo(L.transactions);
      await expectSoon(find.text(L.emptyStateTitle), 'Transactions (empty account): no empty state');
      await drawerGo(L.budgets);
      await expectSoon(find.text(L.noBudgetsYet), 'Budgets (empty account): no empty state');
      await drawerGo(L.goals);
      await expectSoon(find.text(L.noGoalsYet), 'Goals (empty account): no empty state');
      await drawerGo(L.outflowAnalytics);
      await expectSoon(find.text(L.noDataAvailable), 'Outflow analytics (empty account): no "no data" state');
      await drawerGo(L.financialReports);
      await settle(3000);
    });
  });
}
