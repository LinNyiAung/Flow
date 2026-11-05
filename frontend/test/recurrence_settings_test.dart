import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/recurring_transaction.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/recurrence_settings.dart';

final _date = DateTime(2026, 11, 5); // a Thursday

Future<List<TransactionRecurrence?>> _pump(
  WidgetTester tester, {
  TransactionRecurrence? initial,
}) async {
  final changes = <TransactionRecurrence?>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('my')],
      home: Scaffold(
        body: SingleChildScrollView(
          child: RecurrenceSettings(
            initialRecurrence: initial,
            transactionDate: _date,
            onRecurrenceChanged: changes.add,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return changes;
}

void main() {
  testWidgets(
    'has no on/off switch of its own; the schedule shows straight away',
    (tester) async {
      await _pump(tester);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('Recurring Transaction'), findsNothing);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Weekly'), findsOneWidget);
    },
  );

  testWidgets(
    'opening without a recurrence turns repeat on with a monthly default',
    (tester) async {
      final changes = await _pump(tester);
      expect(changes, hasLength(1));
      final r = changes.single!;
      expect(r.enabled, isTrue);
      expect(r.config!.frequency, RecurrenceFrequency.monthly);
      expect(r.config!.dayOfMonth, 5);
    },
  );

  testWidgets('opening an existing schedule keeps it and reports nothing', (
    tester,
  ) async {
    final changes = await _pump(
      tester,
      initial: TransactionRecurrence(
        enabled: true,
        config: RecurrenceConfig(
          frequency: RecurrenceFrequency.weekly,
          dayOfWeek: 2,
        ),
      ),
    );
    expect(changes, isEmpty);
    expect(find.text('Repeat On'), findsOneWidget);
  });

  testWidgets('choosing a frequency reports the new schedule', (tester) async {
    final changes = await _pump(tester);
    await tester.tap(find.text('Weekly'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final r = changes.last!;
    expect(r.enabled, isTrue);
    expect(r.config!.frequency, RecurrenceFrequency.weekly);
    expect(r.config!.dayOfWeek, 3); // Thursday, 0 = Monday
  });
}
