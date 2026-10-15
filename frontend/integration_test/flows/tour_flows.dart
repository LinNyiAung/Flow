import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/ai/ai_chat_screen.dart';
import 'package:frontend/screens/budgets/budget_detail_screen.dart';
import 'package:frontend/screens/budgets/budgets_screen.dart';
import 'package:frontend/screens/budgets/create_budget_screen.dart';
import 'package:frontend/screens/goals/add_goal_screen.dart';
import 'package:frontend/screens/goals/goal_detail_screen.dart';
import 'package:frontend/screens/goals/goals_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/insights/insights_screen.dart';
import 'package:frontend/screens/notifications/notifications_screen.dart';
import 'package:frontend/screens/report/reports_screen.dart';
import 'package:frontend/screens/settings/settings_screen.dart';
import 'package:frontend/screens/transactions/add_transaction_screen.dart';
import 'package:frontend/screens/transactions/edit_transaction_screen.dart';
import 'package:frontend/screens/transactions/transactions_list_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/recurrence_settings.dart';

import '../support/accounts.dart';
import '../support/harness.dart';

const bool kLargeText = bool.fromEnvironment('E2E_LARGE_TEXT');

final _burmese = RegExp(r'[က-႟]');
final _latinWord = RegExp(r'[A-Za-z]{3,}');
const _allowLatin = {
  'Toe Pwar', 'USD', 'MMK', 'THB', 'PDF', 'ENGLISH', 'English', 'Myanmar', 'AI', 'Gmail', 'Viber',
};

/// In Burmese mode, logs texts that look like untranslated English.
void reportEnglish(String where) {
  final hits = <String>{};
  for (final t in visibleTexts()) {
    if (_burmese.hasMatch(t)) continue;
    if (!_latinWord.hasMatch(t)) continue;
    if (_allowLatin.contains(t)) continue;
    if (t.contains('@')) continue;
    hits.add(t.length > 60 ? '${t.substring(0, 60)}…' : t);
  }
  if (hits.isNotEmpty) {
    // ignore: avoid_print
    print('E2E_ENGLISH|${E2E.test}|$where|${hits.join(' ¦ ')}');
  }
}

Future<void> _visit(String label, AppLocalizations l, Future<void> Function() body) async {
  step('tour: $label');
  try {
    await body();
    await settle(800);
    if (l.locale.languageCode == 'my') reportEnglish(label);
  } on TestFailure catch (e) {
    // A finder that did not match (e.g. a chip pushed out of a horizontal
    // list by long/large text) only skips the rest of this stop; errors
    // and overflows are still collected by the harness.
    // ignore: avoid_print
    print('E2E_TOUR_SKIP|${E2E.test}|$label|${(e.message ?? '').split(RegExp(r'[\r\n]')).first}');
    try {
      await hideKeyboard();
      await goHome();
    } catch (_) {}
  }
}

Future<void> _scrollThrough({int swipes = 6}) async {
  for (var i = 0; i < swipes; i++) {
    final s = find.byType(Scrollable).hitTestable();
    if (s.evaluate().isEmpty) return;
    await T.drag(s.first, const Offset(0, -350), warnIfMissed: false);
    await settle(300);
    if (l_reportHook != null) l_reportHook!();
  }
  for (var i = 0; i < swipes; i++) {
    final s = find.byType(Scrollable).hitTestable();
    if (s.evaluate().isEmpty) return;
    await T.drag(s.first, const Offset(0, 500), warnIfMissed: false);
    await settle(200);
  }
}

void Function()? l_reportHook;

Future<void> _closeSheet() async {
  if (find.byType(BottomSheet).evaluate().isNotEmpty) {
    await back();
  }
}

/// Visits every main screen (and key sheets/dialogs) only to surface
/// exceptions and overflows.
Future<void> mainScreenTour(AppLocalizations l) async {
  l_reportHook = l.locale.languageCode == 'my' ? () => reportEnglish('${E2E.step} (scrolled)') : null;

  await _visit('home', l, () async {
    await waitFor(find.byType(HomeScreen));
    await settle(2500);
    await _scrollThrough(swipes: 5);
  });

  await _visit('home currency sheet', l, () async {
    final pill = find.byIcon(Icons.expand_more_rounded);
    if (pill.evaluate().isNotEmpty) {
      await tap(pill.first);
      await settle(2000);
      if (l.locale.languageCode == 'my') reportEnglish('home currency sheet');
      await _closeSheet();
    }
  });

  await _visit('add transaction', l, () async {
    await tap(find.byTooltip(l.addTransactionFabTooltip).last);
    await settle(800);
    if (l.locale.languageCode == 'my') reportEnglish('add options sheet');
    await tap(find.text(l.manualEntry));
    await waitFor(find.byType(AddTransactionScreen));
    await settle(1500);
    for (final k in '123456789012'.split('')) {
      await tapKey('keypad-$k', settleMs: 60);
    }
    await tap(find.byIcon(Icons.category_rounded).first);
    await settle(1000);
    final tiles = find.byType(ListTile);
    if (tiles.evaluate().isNotEmpty) {
      await tap(tiles.first);
      await settle(600);
    }
    await _closeSheet();
    final sw = find.descendant(of: find.byType(AddTransactionScreen), matching: find.byType(Switch));
    await tap(sw.last);
    await waitFor(find.byType(RecurrenceSettings));
    await settle(2000);
    for (final f in [l.weekly, l.annually, l.monthly]) {
      final ff = find.descendant(of: find.byType(RecurrenceSettings), matching: find.text(f));
      if (ff.evaluate().isNotEmpty) {
        await tap(ff.first);
        await settle(1200);
      }
    }
    if (l.locale.languageCode == 'my') reportEnglish('repeat sheet');
    final done = find.descendant(of: find.byType(BottomSheet), matching: find.text(l.doneLabel));
    await scrollTo(done, scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
    await tap(done);
    if (l.locale.languageCode == 'my') reportEnglish('add transaction with repeat');
    await tap(find.byIcon(Icons.notes_rounded));
    await settle(600);
    await tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(l.dialogCancel)));
    await tap(find.byIcon(Icons.close_rounded).first);
    await settle(800);
  });

  await _visit('transactions list', l, () async {
    await drawerGo(l.transactions);
    await waitFor(find.byType(TransactionsListScreen));
    await settle(2500);
    await tap(find.byIcon(Icons.swap_vert_rounded));
    await _closeSheet();
    await tap(find.byIcon(Icons.currency_exchange_rounded));
    await _closeSheet();
    await _scrollThrough(swipes: 3);
  });

  await _visit('edit transaction', l, () async {
    final rows = find.descendant(of: find.byType(TransactionsListScreen), matching: find.byType(ListTile));
    final inks = find.descendant(of: find.byType(TransactionsListScreen), matching: find.byType(InkWell));
    final target = rows.evaluate().isNotEmpty ? rows : inks;
    if (target.evaluate().length > 3) {
      await tap(target.at(3));
      if (await waitFor(find.byType(EditTransactionScreen), timeout: const Duration(seconds: 8), orNull: true)) {
        await settle(1500);
        await _scrollThrough(swipes: 3);
        if (l.locale.languageCode == 'my') reportEnglish('edit transaction');
        await back();
      }
    }
  });

  await _visit('budgets', l, () async {
    await drawerGo(l.budgets);
    await waitFor(find.byType(BudgetsScreen));
    await settle(2500);
    await _scrollThrough(swipes: 3);
  });

  await _visit('budget detail', l, () async {
    final card = find.text('Monthly essentials');
    if (await scrollTo(card, maxSwipes: 5)) {
      await tap(card.first);
      await waitFor(find.byType(BudgetDetailScreen));
      await settle(1500);
      await _scrollThrough(swipes: 4);
      if (l.locale.languageCode == 'my') reportEnglish('budget detail');
      await back();
    }
  });

  await _visit('create budget', l, () async {
    await tap(find.byTooltip(l.createNewBudget));
    await waitFor(find.byType(CreateBudgetScreen));
    await settle(1500);
    await _scrollThrough(swipes: 4);
    await scrollTo(find.text(l.categoryBudgets));
    await tap(buttonWithText<TextButton>(l.add));
    await settle(2000);
    final chips = find.descendant(of: find.byType(BottomSheet), matching: find.byType(GestureDetector));
    if (chips.evaluate().isNotEmpty) await tap(chips.first);
    await settle(800);
    if (l.locale.languageCode == 'my') reportEnglish('category cap sheet');
    await _closeSheet();
    await back();
  });

  await _visit('goals', l, () async {
    await drawerGo(l.goals);
    await waitFor(find.byType(GoalsScreen));
    await settle(2500);
    await _scrollThrough(swipes: 4);
  });

  await _visit('goal detail + manage funds', l, () async {
    final g = find.text('Emergency fund');
    if (await scrollTo(g, maxSwipes: 5)) {
      await tap(g.first);
      await waitFor(find.byType(GoalDetailScreen));
      await settle(1500);
      await _scrollThrough(swipes: 3);
      await tap(find.text(l.manageFunds).last);
      await settle(1000);
      if (l.locale.languageCode == 'my') reportEnglish('manage funds sheet');
      await hideKeyboard();
      await _closeSheet();
      await tap(find.byIcon(Icons.edit_rounded).first);
      await settle(1000);
      if (l.locale.languageCode == 'my') reportEnglish('edit goal sheet');
      await hideKeyboard();
      await _closeSheet();
      await back();
    }
    final overdue = find.text('Trip to Bagan');
    if (await scrollTo(overdue, maxSwipes: 5)) {
      await tap(overdue.first);
      await waitFor(find.byType(GoalDetailScreen));
      await settle(1500);
      if (l.locale.languageCode == 'my') reportEnglish('overdue goal detail');
      await back();
    }
  });

  await _visit('add goal', l, () async {
    await tap(find.byTooltip(l.createNewGoal));
    await waitFor(find.byType(AddGoalScreen));
    await settle(1500);
    await _scrollThrough(swipes: 3);
    await back();
  });

  for (final a in [l.outflowAnalytics, l.inflowAnalytics]) {
    await _visit(a, l, () async {
      await drawerGo(a);
      await settle(3500);
      for (final p in [l.daily, l.yearly, l.custom, l.monthly]) {
        final f = find.text(p);
        if (f.evaluate().isNotEmpty) {
          await tap(f.first);
          await settle(1500);
        }
      }
      await _scrollThrough(swipes: 4);
    });
  }

  await _visit('reports', l, () async {
    await drawerGo(l.financialReports);
    await waitFor(find.byType(ReportsScreen));
    await settle(4000);
    await _scrollThrough(swipes: 4);
    for (final p in [l.week, l.year, l.month]) {
      final f = find.text(p);
      if (f.evaluate().isNotEmpty) {
        await tap(f.first);
        await settle(3000);
      }
    }
    final chip = find.text(l.allCurrencies);
    if (chip.evaluate().isNotEmpty) {
      await tap(chip.first);
      await tap(find.textContaining('USD · ').last);
      await settle(4000);
      await _scrollThrough(swipes: 5);
      if (l.locale.languageCode == 'my') reportEnglish('single-currency report');
      final share = find.byIcon(Icons.ios_share_rounded);
      if (share.evaluate().isNotEmpty) {
        await tap(share);
        await settle(800);
        if (l.locale.languageCode == 'my') reportEnglish('export sheet');
        await _closeSheet();
      }
    }
  });

  await _visit('insights', l, () async {
    await drawerGo(l.aiInsights);
    await waitFor(find.byType(InsightsScreen));
    await waitAny([find.textContaining('summary'), find.textContaining('အကျဉ်းချုပ်'), find.text(l.tryAgain)],
        timeout: const Duration(seconds: 60));
    await settle(1500);
    await _scrollThrough(swipes: 4);
  });

  await _visit('chat', l, () async {
    await drawerGo(l.aiAssistant);
    await waitFor(find.byType(AiChatScreen));
    await settle(2500);
    await _scrollThrough(swipes: 2);
  });

  await _visit('subscription', l, () async {
    await drawerGo(l.subscription);
    await settle(2000);
    await _scrollThrough(swipes: 3);
  });

  await _visit('notifications', l, () async {
    await goHome();
    await tap(find.byIcon(Icons.notifications_rounded).first);
    await waitFor(find.byType(NotificationsScreen));
    await settle(2000);
    await _scrollThrough(swipes: 2);
    await back();
  });

  await _visit('settings', l, () async {
    await drawerGo(l.settings);
    await waitFor(find.byType(SettingsScreen));
    await settle(1000);
    await _scrollThrough(swipes: 4);
  });

  for (final row in [
    l.editProfile,
    l.changePassword,
    l.language,
    l.currency,
    l.theme,
    l.notificationSettings,
    l.privacyPolicyTitle,
    l.termsAndConditionsTitle,
    l.sendFeedback,
  ]) {
    await _visit('settings → $row', l, () async {
      if (!await scrollTo(find.text(row), maxSwipes: 8)) return;
      await tap(find.text(row).first);
      await settle(2500);
      await _scrollThrough(swipes: 4);
      await back();
      await waitFor(find.byType(SettingsScreen));
    });
  }

  await _visit('about dialog', l, () async {
    if (await scrollTo(find.text(l.aboutToePwar), maxSwipes: 8)) {
      await tap(find.text(l.aboutToePwar).first);
      await settle(1200);
      if (l.locale.languageCode == 'my') reportEnglish('about dialog');
      await back();
    }
  });

  await _visit('drawer', l, () async {
    await goHome();
    await openDrawer();
    await settle(600);
    await back();
  });
}

void tourFlows() {
  group('13 Myanmar tour', () {
    e2eTest('tour: Myanmar user visits every main screen (errors/overflows only)', (t) async {
      await login(myanmar);
      await expectSoon(find.text(LM.availableToSpend), 'Myanmar user: Home not shown in Burmese after login');
      await mainScreenTour(LM);
    }, timeout: const Duration(minutes: 15));
  });

  group('14 Large text tour', () {
    e2eTest('tour: premium user, large font scale (run with font_scale 1.3 + E2E_LARGE_TEXT)', (t) async {
      final scale = MediaQuery.textScalerOf(t.element(find.byType(Scaffold).first)).scale(10) / 10;
      // ignore: avoid_print
      print('E2E_INFO|text scale = $scale');
      await login(premium);
      await mainScreenTour(L);
    }, timeout: const Duration(minutes: 15), skip: !kLargeText);

    e2eTest('tour: Myanmar user, large font scale', (t) async {
      await login(myanmar);
      await mainScreenTour(LM);
    }, timeout: const Duration(minutes: 15), skip: !kLargeText);
  });
}
