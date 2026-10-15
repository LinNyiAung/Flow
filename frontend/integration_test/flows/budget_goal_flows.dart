import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/budgets/ai_budget_suggestion_screen.dart';
import 'package:frontend/screens/budgets/budget_detail_screen.dart';
import 'package:frontend/screens/budgets/budgets_screen.dart';
import 'package:frontend/screens/budgets/create_budget_screen.dart';
import 'package:frontend/screens/budgets/edit_budget_screen.dart';
import 'package:frontend/screens/goals/add_goal_screen.dart';
import 'package:frontend/screens/goals/goal_detail_screen.dart';
import 'package:frontend/screens/goals/goals_screen.dart';
import 'package:frontend/screens/subscription/subscription_screen.dart';

import '../support/accounts.dart';
import '../support/harness.dart';

String _stamp() => DateTime.now().millisecondsSinceEpoch.toString().substring(8);

Future<void> openBudgets() async {
  await drawerGo(L.budgets);
  await waitFor(find.byType(BudgetsScreen));
  await settle(2000);
}

Future<void> addCategoryCap(String mainCategory, String amount) async {
  step('add category cap $mainCategory $amount');
  await tap(buttonWithText<TextButton>(L.add));
  final sheet = find.byType(BottomSheet);
  await waitFor(sheet);
  final chip = find.descendant(of: sheet, matching: find.text(mainCategory));
  await waitFor(chip, timeout: const Duration(seconds: 15));
  await tap(chip.first);
  await enter(find.descendant(of: sheet, matching: find.byType(TextField)), amount);
  await hideKeyboard();
  await tap(find.descendant(of: sheet, matching: find.widgetWithText(FilledButton, L.save)));
  await settle(800);
}

Future<void> openGoals() async {
  await drawerGo(L.goals);
  await waitFor(find.byType(GoalsScreen));
  await settle(2000);
}

Future<void> manageFunds({required bool add, required String amount}) async {
  step('${add ? 'add' : 'withdraw'} $amount');
  await tap(find.text(L.manageFunds).last);
  final sheet = find.byType(BottomSheet);
  await waitFor(sheet);
  if (!add) {
    await tap(find.descendant(of: sheet, matching: find.text(L.withdraw)).first);
  }
  await enter(find.descendant(of: sheet, matching: find.byType(TextField)), amount);
  await hideKeyboard();
  await tap(find.descendant(of: sheet, matching: find.widgetWithText(ElevatedButton, add ? L.add : L.withdraw)));
  await settle(2500);
}

void budgetFlows() {
  group('05 Budgets', () {
    e2eTest('budgets: list + detail', (t) async {
      await login(premium);
      await openBudgets();
      step('seeded budgets listed');
      for (final n in ['Monthly essentials', 'Weekly fun']) {
        check(await scrollTo(find.text(n), maxSwipes: 6), 'Budgets list: "$n" missing');
      }
      await scrollTo(find.text('Monthly essentials'), dy: 300);
      step('filter All / currency MMK');
      await tap(find.text(L.filterChipAll).first);
      await settle(1500);
      await tap(find.byIcon(Icons.currency_exchange_rounded).first);
      final mmkOption = find.textContaining('MMK');
      if (await waitFor(mmkOption, timeout: const Duration(seconds: 5), orNull: true)) {
        await tap(mmkOption.last);
        await settle(1500);
        check(await scrollTo(find.text('MMK groceries'), maxSwipes: 4), 'MMK filter: "MMK groceries" missing');
        check(find.text('Monthly essentials').evaluate().isEmpty, 'MMK filter still shows the USD budget');
        await tap(find.byIcon(Icons.currency_exchange_rounded).first);
        await tap(find.text(L.allCurrencies).last);
        await settle(1500);
      }
      step('open detail');
      await scrollTo(find.text('Monthly essentials'));
      await tap(find.text('Monthly essentials').first);
      await waitFor(find.byType(BudgetDetailScreen));
      await settle(1500);
      check(hasTextContaining(L.used), 'Budget detail: "% used" progress missing');
      await scrollTo(find.text(L.categoryBudgets));
      for (final c in ['Food & Daily Living', 'Transportation', 'Entertainment & Leisure']) {
        check(await scrollTo(find.text(c), maxSwipes: 6), 'Budget detail: category "$c" missing');
      }
      await back();
    });

    e2eTest('budgets: create (2 categories) → edit (rename + allocation) → delete', (t) async {
      await login(premium);
      await openBudgets();
      final name = 'E2E budget ${_stamp()}';
      step('create');
      await tap(find.byTooltip(L.createNewBudget));
      await waitFor(find.byType(CreateBudgetScreen));
      await settle(1000);
      await enter(find.widgetWithText(TextFormField, L.budgetName), name);
      await hideKeyboard();
      await tap(find.text(L.month).first);
      await scrollTo(find.text(L.categoryBudgets));
      await addCategoryCap('Transportation', '150');
      await addCategoryCap('Shopping & Lifestyle', '200');
      check(hasText(r'$350.00'), 'Create budget: total of the two caps (\$350.00) not shown');
      step('submit create');
      await tap(find.descendant(of: find.byType(AppBar), matching: find.text(L.createBudget)).last);
      await expectSoon(find.byType(BudgetsScreen), 'Creating a budget did not return to the list', timeout: const Duration(seconds: 25));
      await expectSoon(find.text(L.budgetCreatedSuccessfully), 'No "budget created" snackbar', timeout: const Duration(seconds: 5));
      final listed = await scrollTo(find.text(name), maxSwipes: 8);
      check(listed, 'New budget "$name" not in the list');
      if (!listed) return;
      step('open new budget');
      await tap(find.text(name).first);
      await waitFor(find.byType(BudgetDetailScreen));
      await settle(1200);
      step('edit');
      await tap(find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.edit_rounded)));
      await waitFor(find.byType(EditBudgetScreen));
      await settle(1200);
      final renamed = '$name ed';
      await enter(find.widgetWithText(TextFormField, L.budgetName), renamed);
      await hideKeyboard();
      await scrollTo(find.text('Transportation'));
      final editIcons = find.descendant(of: find.byType(EditBudgetScreen), matching: find.byIcon(Icons.edit_rounded));
      await tap(editIcons.first);
      final sheet = find.byType(BottomSheet);
      await waitFor(sheet);
      await enter(find.descendant(of: sheet, matching: find.byType(TextField)), '175');
      await hideKeyboard();
      await tap(find.descendant(of: sheet, matching: find.widgetWithText(FilledButton, L.save)));
      await settle(800);
      check(hasText(r'$175.00'), 'Edit budget: changed allocation \$175.00 not shown');
      await tap(find.descendant(of: find.byType(AppBar), matching: find.text(L.save)).last);
      await expectSoon(find.text(L.budgetUpdatedSuccessfully), 'No "budget updated" snackbar');
      await settle(1500);
      check(hasText(renamed), 'Budget detail does not show the new name "$renamed"');
      check(await scrollTo(find.textContaining('175.00'), maxSwipes: 6), 'Budget detail does not show the new \$175 allocation');
      step('delete');
      await tap(find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.delete_rounded)));
      await tap(find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(FilledButton, L.delete)));
      await expectSoon(find.byType(BudgetsScreen), 'Deleting the budget did not return to the list');
      await expectSoon(find.text(L.budgetDeletedSuccessfully), 'No "budget deleted" snackbar', timeout: const Duration(seconds: 5));
      await settle(1500);
      check(find.text(renamed).evaluate().isEmpty, 'Deleted budget still listed');
    });

    e2eTest('budgets: AI suggestion (premium, fake OpenAI) fails gracefully; free → paywall', (t) async {
      await login(premium);
      await openBudgets();
      await tap(find.byTooltip(L.createNewBudget));
      await waitFor(find.byType(CreateBudgetScreen));
      step('generate AI budget');
      await tap(find.text(L.generateAiBudget));
      await waitFor(find.byType(AIBudgetSuggestionScreen));
      final r = await waitAny([find.text(L.failedToGenerateSuggestion), find.text(L.suggestedBudgetPlan)],
          timeout: const Duration(seconds: 100));
      check(r >= 0, 'AI budget suggestion neither showed a result nor an error within 100 s (${visibleTexts().take(20).join(' | ')})');
      if (r == 1) {
        // The fake OpenAI returns an empty plan (no categories, total 0).
        final hasCats = find.text(L.useThisBudget).evaluate().isNotEmpty || await scrollTo(find.text(L.useThisBudget), maxSwipes: 6);
        // ignore: avoid_print
        print('E2E_INFO|AI suggestion shown; useThisBudget visible=$hasCats; texts=${visibleTexts().take(30).join(' | ')}');
      }
      if (r == 0) {
        step('try again');
        await tap(find.text(L.tryAgain));
        await waitAny([find.text(L.failedToGenerateSuggestion), find.text(L.useThisBudget)],
            timeout: const Duration(seconds: 100));
      } else if (r == 1 && find.text(L.useThisBudget).evaluate().isNotEmpty) {
        step('use empty AI plan');
        await tap(find.text(L.useThisBudget));
        await waitFor(find.byType(CreateBudgetScreen));
        await settle(800);
        step('save with AI plan (no categories)');
        await tap(find.descendant(of: find.byType(AppBar), matching: find.text(L.createBudget)).last);
        await settle(1500);
        check(find.byType(CreateBudgetScreen).evaluate().isNotEmpty, 'An empty AI plan (0 categories) was saved as a budget');
      }
      await goHome();
      await logout();
      step('free user');
      await login(free);
      await openBudgets();
      await tap(find.byTooltip(L.createNewBudget));
      await waitFor(find.byType(CreateBudgetScreen));
      await tap(find.text(L.generateAiBudget));
      await expectSoon(find.byType(SubscriptionScreen), 'Free user tapping "Generate AI budget" not sent to the paywall');
    });
  });
}

void goalFlows() {
  group('06 Goals', () {
    e2eTest('goals: list incl. overdue + achieved; extend overdue date', (t) async {
      await login(premium);
      await openGoals();
      step('overdue Trip to Bagan');
      check(await scrollTo(find.text('Trip to Bagan'), maxSwipes: 6), 'Goals: "Trip to Bagan" missing');
      check(hasTextContaining('Overdue'), 'Goals list: no "Overdue" label for the overdue goal');
      step('achieved New laptop');
      check(await scrollTo(find.text('New laptop'), maxSwipes: 6), 'Goals: "New laptop" missing');
      check(hasText(L.achieved.toUpperCase()), 'Goals list: no ACHIEVED pill');
      step('filters');
      await scrollTo(find.text(L.filterChipAll), dy: 400);
      await tap(find.text(L.achieved).first);
      await settle(1500);
      check(find.text('Emergency fund').evaluate().isEmpty, 'Achieved filter still shows active goal');
      await tap(find.text(L.filterChipAll).first);
      await settle(1500);
      step('open overdue goal');
      await scrollTo(find.text('Trip to Bagan'));
      await tap(find.text('Trip to Bagan').first);
      await waitFor(find.byType(GoalDetailScreen));
      await settle(1200);
      check(find.byKey(const ValueKey('goal-overdue-banner')).evaluate().isNotEmpty, 'Goal detail: overdue banner missing');
      step('extend date');
      await tap(find.text(L.goalExtendDate));
      final sheet = find.byType(BottomSheet);
      await waitFor(sheet);
      await tap(find.descendant(of: sheet, matching: find.byIcon(Icons.event_rounded)));
      await waitFor(find.byType(DatePickerDialog));
      // next month, day 15
      final next = find.descendant(of: find.byType(DatePickerDialog), matching: find.byIcon(Icons.chevron_right));
      if (next.evaluate().isNotEmpty) await tap(next.first);
      await settle(600);
      await tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('15')).first);
      await tap(find.text('OK'));
      await tap(find.descendant(of: sheet, matching: find.text(L.save)).last);
      await expectSoon(find.text(L.goalUpdatedSuccessfully), 'Extending an overdue goal: no "goal updated" snackbar');
      await settle(1500);
      check(find.byKey(const ValueKey('goal-overdue-banner')).evaluate().isEmpty,
          'Overdue banner still shown after extending the target date');
      await back();
      await settle(1500);
      step('achieved detail');
      await scrollTo(find.text('New laptop'));
      await tap(find.text('New laptop').first);
      await waitFor(find.byType(GoalDetailScreen));
      await settle(1500);
      check(hasText(L.achieved.toUpperCase()), 'Achieved goal detail has no ACHIEVED pill');
      await back();
    });

    e2eTest('goals: create → contribute → withdraw → over-withdraw → delete', (t) async {
      await login(premium);
      await openGoals();
      final name = 'E2E goal ${_stamp()}';
      step('create');
      await tap(find.byTooltip(L.createNewGoal));
      await waitFor(find.byType(AddGoalScreen));
      await settle(1500);
      final fields = find.byType(TextFormField);
      await enter(fields.at(0), name);
      await enter(fields.at(1), '500');
      await enter(fields.at(2), '50');
      await hideKeyboard();
      await tap(buttonWithText<TextButton>(L.createGoal));
      await expectSoon(find.byType(GoalsScreen), 'Creating a goal did not return to Goals', timeout: const Duration(seconds: 25));
      await expectSoon(find.text(L.goalCreatedSuccessfully), 'No "goal created" snackbar', timeout: const Duration(seconds: 5));
      final listed = await scrollTo(find.text(name), maxSwipes: 8);
      check(listed, 'New goal not listed');
      if (!listed) return;
      await tap(find.text(name).first);
      await waitFor(find.byType(GoalDetailScreen));
      await settle(1200);
      check(hasText(r'$50.00'), 'New goal detail does not show the \$50 initial contribution');
      await manageFunds(add: true, amount: '25');
      await expectSoon(find.text(L.fundsAddedSuccessfully), 'Contribute: no success snackbar');
      check(await waitFor(find.text(r'$75.00'), timeout: const Duration(seconds: 6), orNull: true),
          'Goal current amount not \$75.00 after contributing \$25');
      await manageFunds(add: false, amount: '10');
      await expectSoon(find.text(L.fundsWithdrawnSuccessfully), 'Withdraw: no success snackbar');
      check(await waitFor(find.text(r'$65.00'), timeout: const Duration(seconds: 6), orNull: true),
          'Goal current amount not \$65.00 after withdrawing \$10');
      await manageFunds(add: false, amount: '1000');
      check(find.byType(GoalDetailScreen).evaluate().isNotEmpty, 'Over-withdraw left the goal screen');
      check(!hasText(L.fundsWithdrawnSuccessfully) || hasText(r'$65.00'), 'Over-withdrawing \$1000 from a \$65 goal succeeded');
      await settle(4000);
      step('delete');
      await tap(find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.delete_rounded)));
      await waitFor(find.byType(AlertDialog));
      await tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(L.delete)));
      await expectSoon(find.byType(GoalsScreen), 'Deleting a goal did not return to Goals');
      await expectSoon(find.text(L.goalDeletedSuccessfully), 'No "goal deleted" snackbar', timeout: const Duration(seconds: 5));
      await settle(1500);
      check(find.text(name).evaluate().isEmpty, 'Deleted goal still listed');
    });
  });
}
