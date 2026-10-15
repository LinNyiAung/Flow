import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/transactions/add_transaction_screen.dart';
import 'package:frontend/screens/transactions/edit_transaction_screen.dart';
import 'package:frontend/screens/transactions/transactions_list_screen.dart';
import 'package:intl/intl.dart';

import '../support/accounts.dart';
import '../support/harness.dart';

String _stamp() => DateTime.now().millisecondsSinceEpoch.toString().substring(7);

/// Home/List FAB → "Manual entry".
Future<void> openAddTransaction() async {
  step('open add transaction');
  await tap(find.byTooltip(L.addTransactionFabTooltip).last);
  await tap(find.text(L.manualEntry));
  await waitFor(find.byType(AddTransactionScreen));
  await settle(1200);
}

Future<void> typeAmount(String digits) async {
  for (final ch in digits.split('')) {
    await tapKey('keypad-$ch', settleMs: 120);
  }
}

String amountDisplayText() {
  final texts = find
      .descendant(of: find.byKey(const ValueKey('amount-display')), matching: find.byType(Text))
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '')
      .toList();
  return texts.join('');
}

Future<void> addNote(String note) async {
  step('add note');
  await tap(find.byIcon(Icons.notes_rounded));
  await enter(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), note);
  await tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(L.save)));
}

/// Taps the app-bar "Save" of the add screen.
Future<void> saveAdd() async {
  step('save add');
  await tap(find.descendant(of: find.byType(AppBar), matching: find.text(L.save)));
}

/// Picks a category through the category sheet (first main / first sub
/// unless names are given).
Future<(String, String)> pickCategory({String? main, String? sub}) async {
  step('pick category');
  await tap(find.byIcon(Icons.category_rounded).first);
  await waitFor(find.text(L.pickCategoryTitle));
  final sheetTiles = find.byType(ListTile);
  await waitFor(sheetTiles);
  String mainName;
  if (main != null) {
    await tap(find.descendant(of: sheetTiles, matching: find.text(main)));
    mainName = main;
  } else {
    final title = (T.widget<ListTile>(sheetTiles.first).title as Text).data!;
    await tap(sheetTiles.first);
    mainName = title;
  }
  await waitFor(find.text(L.chooseSubCategoryTitle));
  String subName;
  final subTiles = find.byType(ListTile);
  if (sub != null) {
    await tap(find.descendant(of: subTiles, matching: find.text(sub)));
    subName = sub;
  } else {
    subName = (T.widget<ListTile>(subTiles.first).title as Text).data!;
    await tap(subTiles.first);
  }
  await settle(600);
  return (mainName, subName);
}

Future<List<dynamic>> apiTransactions(Account a, {int limit = 200}) async {
  final token = await apiToken(a);
  return (await apiGet(token, '/api/transactions?limit=$limit&skip=0')) as List<dynamic>;
}

Future<void> openTransactionsList() async {
  await drawerGo(L.transactions);
  await waitFor(find.byType(TransactionsListScreen));
  await settle(2500);
}

/// Count label in the list ("N transactions").
int? listCount() {
  for (final t in visibleTexts()) {
    final m = RegExp('^(\\d+) ${RegExp.escape(L.transactionsCountSuffix)}\$').firstMatch(t);
    if (m != null) return int.parse(m.group(1)!);
    if (t == L.oneTransactionLabel) return 1;
  }
  return null;
}

/// Trailing amount texts of the visible list rows (e.g. "-$12.50").
List<String> rowAmounts() => visibleTexts()
    .where((t) => RegExp(r'^[+-][\$K฿][\d,]+\.\d\d$').hasMatch(t))
    .toList();

String? homeOutflowStat() {
  // StatTile: label then value; take the value that follows "Outflow".
  final texts = visibleTexts();
  final i = texts.indexOf(L.outflow);
  if (i < 0) return null;
  for (var j = i + 1; j < texts.length && j < i + 4; j++) {
    if (RegExp(r'^[\$K฿][\d,]+\.\d\d$').hasMatch(texts[j])) return texts[j];
  }
  return null;
}

Future<void> pickDateRangeToday() async {
  step('date range = today');
  await tap(find.text(L.selectDateRangeButton));
  await settle(800);
  // Switch to text input mode for determinism.
  final editIcon = find.byIcon(Icons.edit_outlined);
  if (editIcon.evaluate().isNotEmpty) {
    await tap(editIcon.first);
  } else if (find.byIcon(Icons.edit).evaluate().isNotEmpty) {
    await tap(find.byIcon(Icons.edit).first);
  }
  final today = DateFormat('MM/dd/yyyy').format(DateTime.now());
  final fields = find.byType(TextField);
  await waitFor(fields);
  await enter(fields.at(0), today);
  await enter(fields.at(1), today);
  for (final label in ['OK', 'Save', 'SAVE']) {
    if (find.text(label).evaluate().isNotEmpty) {
      await tap(find.text(label).last);
      break;
    }
  }
  await settle(2000);
}

void transactionFlows() {
  group('03 Transactions', () {
    e2eTest('tx: add outflow via keypad + quick chip + note; Home updates', (t) async {
      await login(premium);
      final before = homeOutflowStat();
      await openAddTransaction();
      final note = 'e2e outflow ${_stamp()}';
      step('keypad 12.50');
      await typeAmount('12.50');
      check(amountDisplayText().contains('12.50'), 'Amount display shows "${amountDisplayText()}" instead of 12.50');
      step('quick chip');
      final chip = find.byType(ActionChip);
      await waitFor(chip, reason: 'quick-pick category chips');
      final chipLabel = ((t.widget<ActionChip>(chip.first)).label as Text).data!;
      await tap(chip.first);
      check(find.descendant(of: find.byType(AddTransactionScreen), matching: find.text(chipLabel)).evaluate().length >= 2,
          'Quick chip "$chipLabel" did not fill the category row');
      await addNote(note);
      check(hasText(note), 'Note not shown on the add screen after saving the note dialog');
      await saveAdd();
      await expectSoon(find.byType(HomeScreen), 'Saving an outflow did not return to Home');
      await expectSoon(find.text(L.transactionAdded), 'No "Transaction added" snackbar after save', timeout: const Duration(seconds: 6));
      step('verify via API');
      final txs = await apiTransactions(premium, limit: 20);
      final match = txs.where((x) => x['description'] == note).toList();
      check(match.length == 1 && (match.first['amount'] as num) == 12.5 && match.first['type'] == 'outflow',
          'Created outflow not found / wrong in API: $match');
      step('home outflow stat updated');
      await settle(2500);
      final after = homeOutflowStat();
      check(before != after, 'Home outflow total did not change after adding \$12.50 (before $before, after $after)');
    });

    e2eTest('tx: add inflow with category sheet', (t) async {
      await login(premium);
      await openAddTransaction();
      step('switch to inflow');
      await tap(find.descendant(of: find.byType(AddTransactionScreen), matching: find.text(L.inflow)).first);
      await settle(1500);
      await typeAmount('2000');
      final cat = await pickCategory();
      check(hasText(cat.$2), 'Picked sub-category "${cat.$2}" not shown on the add screen');
      final note = 'e2e inflow ${_stamp()}';
      await addNote(note);
      await saveAdd();
      await expectSoon(find.byType(HomeScreen), 'Saving an inflow did not return to Home');
      final txs = await apiTransactions(premium, limit: 20);
      final match = txs.where((x) => x['description'] == note).toList();
      check(match.length == 1 && match.first['type'] == 'inflow' && match.first['main_category'] == cat.$1,
          'Created inflow not found / wrong in API: $match');
    });

    e2eTest('tx: amount validation + rapid type toggle', (t) async {
      await login(premium);
      await openAddTransaction();
      step('save empty');
      await saveAdd();
      await expectSoon(find.text(L.validationAmountRequired), 'Add: empty amount shows no validation message');
      await settle(4500); // snackbar away
      step('amount without category');
      await typeAmount('5');
      await saveAdd();
      await expectSoon(find.text(L.validationMainCategoryRequired), 'Add: missing category shows no validation message');
      await settle(4500);
      step('zero amount');
      await tapKey('keypad-⌫');
      await typeAmount('0');
      await tap(find.byType(ActionChip).first);
      await saveAdd();
      await expectSoon(find.text(L.validationAmountPositive), 'Add: zero amount not rejected');
      await settle(4500);
      step('backspace / decimals');
      await typeAmount('7.999');
      check(amountDisplayText().endsWith('7.99'), 'Keypad allowed more than 2 decimals: ${amountDisplayText()}');
      step('rapid toggle outflow/inflow/outflow then save');
      final outSeg = find.descendant(of: find.byType(AddTransactionScreen), matching: find.text(L.outflow)).first;
      final inSeg = find.descendant(of: find.byType(AddTransactionScreen), matching: find.text(L.inflow)).first;
      await t.tap(inSeg);
      await t.pump(const Duration(milliseconds: 30));
      await t.tap(outSeg);
      await t.pump(const Duration(milliseconds: 30));
      await t.tap(inSeg);
      await t.pump(const Duration(milliseconds: 30));
      await t.tap(outSeg);
      await settle(2500);
      final chips = find.byType(ActionChip);
      await waitFor(chips);
      final label = ((t.widget<ActionChip>(chips.first)).label as Text).data!;
      await tap(chips.first);
      await saveAdd();
      final r = await waitAny([find.byType(HomeScreen), find.textContaining('Invalid')], timeout: const Duration(seconds: 15));
      final closed = await waitGone(find.byType(AddTransactionScreen), timeout: const Duration(seconds: 10));
      if (r == 1 || !closed) {
        appBug('After rapidly toggling Outflow/Inflow/Outflow, saving an outflow with quick chip "$label" failed: '
            '${visibleTexts().take(30).join(' | ')}');
      }
    });

    e2eTest('tx: 12-digit amount does not overflow (add, home, list)', (t) async {
      await login(free);
      await openAddTransaction();
      step('type 14 digits');
      await typeAmount('99999999999999');
      final shown = amountDisplayText();
      check(shown.replaceAll(RegExp(r'[^\d]'), '').length == 12,
          'Keypad should cap at 12 digits, display shows "$shown"');
      await tap(find.byType(ActionChip).first);
      final note = 'e2e huge ${_stamp()}';
      await addNote(note);
      await saveAdd();
      final r = await waitAny([find.byType(HomeScreen)], timeout: const Duration(seconds: 15));
      check(r == 0, 'Saving a 12-digit amount did not return to Home (visible: ${visibleTexts().take(20).join(' | ')})');
      step('home with huge amount');
      await settle(2500);
      await scrollTo(find.text(L.recentTransactions));
      await settle(800);
      await openTransactionsList();
      step('list with huge amount');
      await settle(1500);
      // cleanup: delete it again (top row is today's)
      final row = find.textContaining('999,999,999,999');
      if (await waitFor(row, timeout: const Duration(seconds: 8), orNull: true)) {
        await tap(row.first);
        await waitFor(find.byType(EditTransactionScreen));
        step('edit screen with huge amount');
        await settle(1000);
        await tap(find.byIcon(Icons.delete_outline_rounded));
        await tap(find.widgetWithText(FilledButton, L.delete));
        await settle(2500);
      } else {
        appBug('12-digit transaction not visible in the transactions list');
      }
    });

    e2eTest('tx: list filters (type, currency, date today) + clear', (t) async {
      await login(premium);
      await openTransactionsList();
      final total = listCount();
      check(total != null && total > 0, 'Transactions list shows no count / no rows');
      step('type = outflow');
      await tap(find.byIcon(Icons.swap_vert_rounded));
      await tap(find.descendant(of: find.byType(ListTile), matching: find.text(L.outflow)));
      await settle(2500);
      final amounts = rowAmounts();
      check(amounts.isNotEmpty && amounts.every((a) => a.startsWith('-')),
          'Outflow filter shows non-outflow rows: ${amounts.take(10)}');
      step('currency = MMK');
      await tap(find.byIcon(Icons.currency_exchange_rounded));
      await tap(find.textContaining('MMK · '));
      await settle(2500);
      final mmk = rowAmounts();
      check(mmk.isNotEmpty && mmk.every((a) => a.startsWith('-K')),
          'Outflow+MMK filter shows other rows: ${mmk.take(10)}');
      step('clear all filters');
      await tap(find.byTooltip(L.clearAllFiltersButton));
      await settle(2500);
      check(listCount() == total, 'Clear filters did not restore the full list (${listCount()} vs $total)');
      await pickDateRangeToday();
      final todayLabel = DateFormat('MMM dd').format(DateTime.now());
      check(hasTextContaining(todayLabel), 'Date chip does not show the picked range');
      final rows = visibleTexts().where((x) => RegExp(r'^[A-Z][a-z]{2} \d\d$').hasMatch(x)).toSet();
      check(rows.every((d) => d == todayLabel), 'Date filter (today) shows rows from other days: $rows');
      step('scroll to load more (pagination)');
      await tap(find.byTooltip(L.clearAllFiltersButton));
      await settle(2000);
      for (var i = 0; i < 12; i++) {
        await t.drag(find.byType(Scrollable).last, const Offset(0, -600), warnIfMissed: false);
        await settle(400);
      }
      await settle(2000);
    });

    e2eTest('tx: edit amount/category/date from list; list refreshes', (t) async {
      await login(premium);
      // Create a dedicated row to edit via the UI.
      await openAddTransaction();
      final note = 'e2e edit ${_stamp()}';
      await typeAmount('33');
      await tap(find.byType(ActionChip).first);
      await addNote(note);
      await saveAdd();
      await waitFor(find.byType(HomeScreen));
      await openTransactionsList();
      step('open the new row');
      final row = find.text('-\$33.00');
      await waitFor(row, reason: 'new \$33 row in list');
      await tap(row.first);
      await waitFor(find.byType(EditTransactionScreen));
      await settle(1500);
      step('change amount to 42');
      final keyFinder = (String k) => find.descendant(
          of: find.byType(EditTransactionScreen),
          matching: k == '⌫' ? find.byIcon(Icons.backspace_rounded) : find.text(k));
      for (var i = 0; i < 6; i++) {
        await tap(keyFinder('⌫'), settleMs: 100);
      }
      await tap(keyFinder('4'), settleMs: 100);
      await tap(keyFinder('2'), settleMs: 100);
      step('change category');
      final cat = await pickCategory();
      step('change date (pick the 1st of this month)');
      await tap(find.byIcon(Icons.event_rounded));
      await settle(800);
      final dayOne = find.descendant(of: find.byType(Dialog), matching: find.text('1'));
      if (await waitFor(dayOne, timeout: const Duration(seconds: 5), orNull: true)) {
        await tap(dayOne.first);
      }
      await tap(find.text('OK'));
      step('update');
      await tap(find.text(L.updateTransactionButton));
      await expectSoon(find.byType(TransactionsListScreen), 'Update did not return to the list');
      await settle(2500);
      final api = (await apiTransactions(premium)).where((x) => x['description'] == note).toList();
      check(api.length == 1 && (api.first['amount'] as num) == 42 && api.first['main_category'] == cat.$1,
          'Edited transaction wrong in API: $api');
      if (api.isNotEmpty) {
        final d = DateTime.parse(api.first['date'] as String);
        check(d.day == 1, 'Edited date not saved as the 1st (got ${api.first['date']})');
      }
      final firstOfMonth = DateFormat('MMM dd').format(DateTime(DateTime.now().year, DateTime.now().month, 1));
      check(await scrollTo(find.text('-\$42.00'), maxSwipes: 30), 'List does not show the edited -\$42.00 row ($firstOfMonth)');
    });

    e2eTest('tx: clearing a note persists (reopen shows no note)', (t) async {
      await login(premium);
      await openAddTransaction();
      final note = 'e2e note ${_stamp()}';
      await typeAmount('21');
      await tap(find.byType(ActionChip).first);
      await addNote(note);
      await saveAdd();
      await waitFor(find.byType(HomeScreen));
      await openTransactionsList();
      final row = find.text('-\$21.00');
      await waitFor(row);
      await tap(row.first);
      await waitFor(find.byType(EditTransactionScreen));
      await settle(1000);
      check(hasText(note), 'Edit screen does not show the saved note');
      step('clear note');
      await tap(find.byIcon(Icons.notes_rounded));
      await enter(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '');
      await tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(L.save)));
      check(!hasText(note), 'Note still shown after clearing it in the dialog');
      await tap(find.text(L.updateTransactionButton));
      await waitFor(find.byType(TransactionsListScreen));
      await settle(2000);
      step('verify cleared note');
      final token = await apiToken(premium);
      final all = (await apiGet(token, '/api/transactions?limit=200&skip=0')) as List;
      final still = all.where((x) => x['description'] == note).toList();
      check(still.isEmpty,
          'BUG: clearing a transaction note does not persist — API still returns description "$note" after Update '
          '(edit_transaction_screen.dart:1169 sends null; api_service omits null description)');
      step('reopen');
      await tap(find.text('-\$21.00').first);
      await waitFor(find.byType(EditTransactionScreen));
      await settle(1000);
      check(!hasText(note), 'Reopened transaction still shows the cleared note "$note"');
      await back();
    });

    e2eTest('tx: delete from list refreshes list; delete from Home shows snackbar', (t) async {
      await login(premium);
      for (final amt in ['17', '18']) {
        await openAddTransaction();
        await typeAmount(amt);
        await tap(find.byType(ActionChip).first);
        await addNote('e2e del $amt ${_stamp()}');
        await saveAdd();
        await waitFor(find.byType(HomeScreen));
        await settle(1500);
      }
      await openTransactionsList();
      final before = listCount();
      step('delete -\$17 from list');
      final row = find.text('-\$17.00');
      await waitFor(row);
      await tap(row.first);
      await waitFor(find.byType(EditTransactionScreen));
      await tap(find.byIcon(Icons.delete_outline_rounded));
      await waitFor(find.text(L.deleteTransactionTitle));
      await tap(find.widgetWithText(FilledButton, L.delete));
      await settle(3000);
      final backOnList = find.byType(TransactionsListScreen).hitTestable().evaluate().isNotEmpty &&
          find.byType(EditTransactionScreen).evaluate().isEmpty;
      check(backOnList, 'After deleting, the app is not back on the transactions list (screen: ${E2E.screen})');
      final api = await apiTransactions(premium, limit: 300);
      check(!api.any((x) => (x['description'] ?? '').toString().startsWith('e2e del 17')),
          'Deleted transaction still exists in the API');
      await settle(1500);
      final stillVisible = find.text('-\$17.00').evaluate().isNotEmpty;
      check(!stillVisible,
          'BUG: deleted row (-\$17.00) is still visible in the Transactions list after delete — the list did not refresh '
          '(edit screen pops with null instead of "deleted")');
      // ignore: avoid_print
      print('E2E_INFO|list count before/after delete: $before / ${listCount()} (page size 50)');

      step('delete -\$18 from Home recent');
      await goHome();
      await scrollTo(find.text('-\$18.00'), maxSwipes: 6);
      final homeRow = find.textContaining('18.00');
      if (await waitFor(homeRow, timeout: const Duration(seconds: 5), orNull: true)) {
        await tap(homeRow.first);
        await waitFor(find.byType(EditTransactionScreen));
        await tap(find.byIcon(Icons.delete_outline_rounded));
        await tap(find.widgetWithText(FilledButton, L.delete));
        final snack = await waitFor(find.text(L.transactionDeleted), timeout: const Duration(seconds: 6), orNull: true);
        check(snack, 'BUG: deleting a transaction opened from Home shows no "Transaction deleted" snackbar '
            '(Home awaits result == "deleted", edit screen pops with null)');
        check(find.byType(HomeScreen).hitTestable().evaluate().isNotEmpty, 'After delete from Home, Home is not visible');
        await settle(2500);
        check(find.textContaining('18.00').evaluate().isEmpty, 'Deleted -\$18 row still visible on Home');
      } else {
        appBug('Newly added -\$18 transaction not visible in Home recent list');
      }
    });
  });
}
