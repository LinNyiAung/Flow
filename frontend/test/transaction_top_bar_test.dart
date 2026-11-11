import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/recurring_transaction.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/transactions/add_transaction_screen.dart';
import 'package:frontend/screens/transactions/edit_transaction_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/app_bar_save_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTransactions extends TransactionProvider {
  final updates = <double>[];

  @override
  Future<bool> updateTransaction({
    required String transactionId,
    TransactionType? type,
    String? mainCategory,
    String? subCategory,
    DateTime? date,
    String? description,
    double? amount,
    Currency? currency,
    BuildContext? context,
    TransactionRecurrence? recurrence,
  }) async {
    updates.add(amount ?? -1);
    return true;
  }
}

/// The server turns the edit down.
class _RejectingTransactions extends TransactionProvider {
  static const message = 'Amount exceeds the allowed limit';

  @override
  String? get writeError => message;

  @override
  Future<bool> updateTransaction({
    required String transactionId,
    TransactionType? type,
    String? mainCategory,
    String? subCategory,
    DateTime? date,
    String? description,
    double? amount,
    Currency? currency,
    BuildContext? context,
    TransactionRecurrence? recurrence,
  }) async =>
      false;
}

/// The server takes its time: the save stays in flight until [finish].
class _SlowTransactions extends TransactionProvider {
  final pending = Completer<bool>();
  int calls = 0;
  void finish() => pending.complete(true);

  @override
  Future<bool> updateTransaction({
    required String transactionId,
    TransactionType? type,
    String? mainCategory,
    String? subCategory,
    DateTime? date,
    String? description,
    double? amount,
    Currency? currency,
    BuildContext? context,
    TransactionRecurrence? recurrence,
  }) {
    calls++;
    return pending.future;
  }
}

Transaction _lunch() {
  final d = DateTime(2026, 11, 10, 12);
  return Transaction(
    id: 't1',
    userId: 'u1',
    type: TransactionType.outflow,
    mainCategory: 'Food & Daily Living',
    subCategory: 'Restaurants',
    date: d,
    amount: 12.5,
    currency: Currency.usd,
    createdAt: d,
    updatedAt: d,
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget Function(BuildContext) screen, {
  required Locale locale,
  required Size size,
  TransactionProvider? transactions,
  void Function(Object?)? onResult,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<TransactionProvider>(create: (_) => transactions ?? TransactionProvider()),
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
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final result = await Navigator.push(context, MaterialPageRoute(builder: screen));
                onResult?.call(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _inBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);

/// Everything in the bar is on screen and nothing overlaps the title.
void _expectBarFits(WidgetTester tester, String title, Finder firstAction, double width) {
  expect(tester.takeException(), isNull);
  final bar = tester.getRect(find.byType(AppBar));
  for (final f in [firstAction, _inBar(find.byType(IconButton)).first]) {
    final r = tester.getRect(f);
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(width));
    expect(r.bottom, lessThanOrEqualTo(bar.bottom));
  }
  final titleFinder = _inBar(find.text(title));
  if (titleFinder.evaluate().isNotEmpty) {
    expect(tester.getRect(titleFinder).right, lessThanOrEqualTo(tester.getRect(firstAction).left));
  }
}

void main() {
  final my = AppLocalizations(const Locale('my'));
  final en = AppLocalizations(const Locale('en'));

  group('Edit transaction', () {
    testWidgets('Save is in the top bar; no Update/Cancel buttons below', (tester) async {
      final transactions = _FakeTransactions();
      Object? result;
      await _pump(
        tester,
        (_) => EditTransactionScreen(transaction: _lunch()),
        locale: const Locale('en'),
        size: const Size(390, 844),
        transactions: transactions,
        onResult: (r) => result = r,
      );

      expect(find.text(en.updateTransactionButton), findsNothing);
      expect(find.text(en.dialogCancel), findsNothing);
      expect(_inBar(find.byIcon(Icons.delete_outline_rounded)), findsOneWidget);
      final save = _inBar(find.text(en.save));
      expect(save, findsOneWidget);

      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(transactions.updates, [12.5]);
      expect(result, true);
    });

    testWidgets('a rejected save says so in a snackbar, not only in the box at the bottom', (tester) async {
      Object? result = 'not popped';
      await _pump(
        tester,
        (_) => EditTransactionScreen(transaction: _lunch()),
        locale: const Locale('en'),
        size: const Size(390, 600),
        transactions: _RejectingTransactions(),
        onResult: (r) => result = r,
      );

      await tester.tap(_inBar(find.text(en.save)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final snack = find.descendant(of: find.byType(SnackBar), matching: find.text(_RejectingTransactions.message));
      expect(snack, findsOneWidget);
      // On screen, where the user is looking.
      final r = tester.getRect(snack);
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(600));
      // Still on the edit screen; Save works again.
      expect(result, 'not popped');
      expect(_inBar(find.text(en.save)), findsOneWidget);
    });

    testWidgets('while saving, delete is disabled and Save does not send twice', (tester) async {
      final transactions = _SlowTransactions();
      await _pump(
        tester,
        (_) => EditTransactionScreen(transaction: _lunch()),
        locale: const Locale('en'),
        size: const Size(390, 844),
        transactions: transactions,
      );
      final delete = find.ancestor(
          of: _inBar(find.byIcon(Icons.delete_outline_rounded)), matching: find.byType(IconButton));
      expect(tester.widget<IconButton>(delete).onPressed, isNotNull);

      await tester.tap(_inBar(find.text(en.save)));
      await tester.pump();
      expect(transactions.calls, 1);
      expect(tester.widget<IconButton>(delete).onPressed, isNull);

      // Tapping delete does nothing: no delete sheet.
      await tester.tap(delete, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.delete_rounded), findsNothing);

      // Nor does tapping Save again.
      await tester.tap(_inBar(find.byType(AppBarSaveButton)), warnIfMissed: false);
      await tester.pump();
      expect(transactions.calls, 1);

      transactions.finish();
      await tester.pumpAndSettle();
    });

    testWidgets('Myanmar 360: title, delete and Save fit the bar', (tester) async {
      await _pump(
        tester,
        (_) => EditTransactionScreen(transaction: _lunch()),
        locale: const Locale('my'),
        size: const Size(360, 780),
      );
      _expectBarFits(tester, my.editTransactionTitle, _inBar(find.byIcon(Icons.delete_outline_rounded)), 360);
      final save = tester.getRect(_inBar(find.text(my.save)));
      expect(save.right, lessThanOrEqualTo(360));
    });
  });

  group('New entry', () {
    for (final locale in const [Locale('my'), Locale('en')]) {
      testWidgets('${locale.languageCode} 360: the title never runs under the mic; X and Save stay', (tester) async {
        final l = AppLocalizations(locale);
        await _pump(tester, (_) => AddTransactionScreen(), locale: locale, size: const Size(360, 780));
        _expectBarFits(tester, l.addTransactionTitle, _inBar(find.byIcon(Icons.mic_rounded)), 360);
        expect(_inBar(find.byIcon(Icons.close_rounded)), findsOneWidget);
        final save = tester.getRect(_inBar(find.text(l.save)));
        expect(save.right, lessThanOrEqualTo(360));
      });
    }
  });
}
