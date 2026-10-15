import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/transactions/add_transaction_screen.dart';
import 'package:frontend/screens/transactions/edit_transaction_screen.dart';
import 'package:frontend/screens/transactions/transactions_list_screen.dart';
import 'package:frontend/widgets/recurrence_settings.dart';

import '../support/accounts.dart';
import '../support/harness.dart';
import 'transaction_flows.dart';

void recurringFlows() {
  group('04 Recurring', () {
    e2eTest('recurring: add transaction with Repeat monthly + preview', (t) async {
      await login(premium);
      await openAddTransaction();
      await typeAmount('45');
      await tap(find.byType(ActionChip).first);
      final note = 'e2e recurring ${DateTime.now().millisecondsSinceEpoch}';
      await addNote(note);
      step('repeat switch on → sheet');
      final repeatSwitch = find.descendant(of: find.byType(AddTransactionScreen), matching: find.byType(Switch));
      await tap(repeatSwitch.last);
      await waitFor(find.byType(RecurrenceSettings));
      step('choose monthly');
      await tap(find.descendant(of: find.byType(RecurrenceSettings), matching: find.text(L.monthly)));
      await settle(1500);
      check(hasText(L.dayOfMonth), 'Monthly recurrence: no day-of-month selector');
      await scrollTo(find.text(L.next5Occurrences),
          scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
      final gotPreview = await waitFor(find.byIcon(Icons.circle), timeout: const Duration(seconds: 10), orNull: true);
      check(gotPreview, 'Recurrence preview did not list upcoming occurrences');
      if (gotPreview) {
        check(find.byIcon(Icons.circle).evaluate().length == 5,
            'Recurrence preview shows ${find.byIcon(Icons.circle).evaluate().length} dates instead of 5');
      }
      step('done');
      await tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(L.doneLabel)));
      check(hasTextContaining('of the month'), 'Repeat row does not summarise the monthly schedule');
      await saveAdd();
      await expectSoon(find.byType(HomeScreen), 'Saving a recurring transaction did not return to Home');
      final api = (await apiTransactions(premium, limit: 30)).where((x) => x['description'] == note).toList();
      check(api.length == 1 && api.first['recurrence']?['enabled'] == true &&
              api.first['recurrence']?['config']?['frequency'] == 'monthly',
          'Recurring transaction not stored with a monthly recurrence: ${api.map((x) => x['recurrence'])}');
    });

    e2eTest('recurring: open + close repeat sheet quickly (preview race)', (t) async {
      await login(premium);
      await openAddTransaction();
      for (var i = 0; i < 3; i++) {
        step('open repeat sheet #$i and close immediately');
        final repeatSwitch = find.descendant(of: find.byType(AddTransactionScreen), matching: find.byType(Switch));
        await tap(repeatSwitch.last, settleMs: 50);
        await waitFor(find.byType(RecurrenceSettings));
        await tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(L.doneLabel)), visible: false, settleMs: 200);
        // turn it off again
        await tap(repeatSwitch.last, settleMs: 200);
        if (find.byType(RecurrenceSettings).evaluate().isNotEmpty) {
          await back();
        }
      }
      await settle(2500);
      await back();
    });

    e2eTest('recurring: edit seeded monthly rent → weekly', (t) async {
      await login(premium);
      await openTransactionsList();
      step('find rent');
      final rent = find.text('-\$900.00');
      final found = await scrollTo(rent, maxSwipes: 30);
      if (!found) {
        appBug('Seeded recurring rent (-\$900.00) not found in the transactions list');
        return;
      }
      check(hasTextContaining('of the month'), 'Recurring rent row does not show its schedule');
      await tap(rent.first);
      await waitFor(find.byType(EditTransactionScreen));
      await settle(1500);
      check(hasTextContaining('of the month'), 'Edit screen Repeat row does not show the monthly schedule');
      step('open repeat sheet');
      await scrollTo(find.text(L.repeatLabel));
      await tap(find.text(L.repeatLabel).first);
      await waitFor(find.byType(RecurrenceSettings));
      await tap(find.descendant(of: find.byType(RecurrenceSettings), matching: find.text(L.weekly)));
      await settle(1500);
      check(hasText(L.repeatOn), 'Weekly recurrence: no weekday selector');
      await tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(L.doneLabel)));
      check(hasTextContaining('Every '), 'Repeat row not updated after choosing weekly');
      step('update');
      await scrollTo(find.text(L.updateTransactionButton));
      await tap(find.text(L.updateTransactionButton));
      await expectSoon(find.byType(TransactionsListScreen), 'Updating the recurring rent did not return to the list');
      final api = (await apiTransactions(premium, limit: 300))
          .where((x) => x['description'] == 'Apartment rent' && x['parent_transaction_id'] == null)
          .toList();
      check(api.isNotEmpty && api.first['recurrence']?['config']?['frequency'] == 'weekly',
          'Rent recurrence not saved as weekly: ${api.map((x) => x['recurrence'])}');
    });
  });
}
