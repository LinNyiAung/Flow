import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/transaction.dart' show Category, TransactionType;
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/budget_provider.dart';
import 'package:frontend/screens/budgets/edit_budget_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what the edit screen would send instead of calling the API.
class _RecordingBudgetProvider extends BudgetProvider {
  double? sentTotal;
  List<CategoryBudget>? sentCategories;
  int calls = 0;

  @override
  Future<bool> updateBudget({
    required String budgetId,
    String? name,
    List<CategoryBudget>? categoryBudgets,
    double? totalBudget,
    String? description,
    bool? autoCreateEnabled,
    bool? autoCreateWithAi,
  }) async {
    calls++;
    sentTotal = totalBudget;
    sentCategories = categoryBudgets;
    return true;
  }
}

CategoryBudget _cat(String name, double cap, double spent) => CategoryBudget(
      mainCategory: name,
      allocatedAmount: cap,
      spentAmount: spent,
      percentageUsed: cap > 0 ? spent / cap * 100 : 0,
      isExceeded: spent > cap,
    );

/// Total $1,500 while the caps add up to $860; Entertainment is already over
/// its cap before any edit.
Budget _budget({double total = 1500}) {
  final now = DateTime.now();
  return Budget(
    id: 'b1',
    userId: 'u1',
    name: 'November',
    period: BudgetPeriod.monthly,
    startDate: DateTime(now.year, now.month, 1),
    endDate: DateTime(now.year, now.month + 1, 0),
    categoryBudgets: [
      _cat('Food & Dining', 500, 200),
      _cat('Entertainment & Leisure', 60, 106.84),
      _cat('Transportation', 300, 0),
    ],
    totalBudget: total,
    totalSpent: 306.84,
    remainingBudget: 1193.16,
    percentageUsed: 20.5,
    status: BudgetStatus.exceeded,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    currency: Currency.usd,
  );
}

Future<List<Category>> _categories(TransactionType _) async => [
      Category(mainCategory: 'Food & Dining', subCategories: const []),
      Category(mainCategory: 'Entertainment & Leisure', subCategories: const []),
      Category(mainCategory: 'Transportation', subCategories: const []),
      Category(mainCategory: 'Shopping', subCategories: const []),
    ];

Future<_RecordingBudgetProvider> _open(WidgetTester tester, {double total = 1500}) async {
  tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final provider = _RecordingBudgetProvider();
  await tester.pumpWidget(
    ChangeNotifierProvider<BudgetProvider>.value(
      value: provider,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('my')],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditBudgetScreen(budget: _budget(total: total), categoriesLoader: _categories),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return provider;
}

/// Opens the cap sheet for the row showing [name] and saves [amount].
Future<void> _editCap(WidgetTester tester, String name, String amount) async {
  final row = find.ancestor(of: find.text(name), matching: find.byType(Row)).first;
  await tester.tap(find.descendant(of: row, matching: find.byIcon(Icons.edit_rounded)));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, amount);
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

Future<void> _saveScreen(WidgetTester tester) async {
  await tester.tap(find.text('Save').first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('opening a budget whose total is above its caps changes nothing', (tester) async {
    await _open(tester);

    expect(find.text('TOTAL CAP'), findsNothing); // no change card
    expect(find.text('This cap is already spent'), findsNothing); // no warning
    expect(find.text(r'$1,500.00'), findsOneWidget); // the current total, as stored
    expect(find.text(r'$860.00'), findsNothing);
  });

  testWidgets('Save without category changes sends the original total', (tester) async {
    final provider = await _open(tester);
    await _saveScreen(tester);

    expect(provider.calls, 1);
    expect(provider.sentTotal, 1500);
  });

  testWidgets('lowering a cap below its spending warns for that category only', (tester) async {
    await _open(tester);
    await _editCap(tester, 'Food & Dining', '150'); // $200 already spent

    expect(find.text('This cap is already spent'), findsOneWidget);
    final body = find.textContaining('already has more spent');
    expect(body, findsOneWidget);
    final text = tester.widget<Text>(body).data!;
    expect(text, startsWith('Food & Dining '));
    expect(text, isNot(contains('Entertainment')));

    // The total moves by the same -$350 the caps moved.
    expect(find.text('TOTAL CAP'), findsOneWidget);
    expect(find.text(r'$1,150.00'), findsOneWidget);
  });

  testWidgets('adding a category raises the total by its cap, and Save sends it', (tester) async {
    final provider = await _open(tester);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shopping'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '100');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('TOTAL CAP'), findsOneWidget);
    expect(find.text(r'$1,600.00'), findsOneWidget);
    expect(find.text('This cap is already spent'), findsNothing);

    await _saveScreen(tester);
    expect(provider.sentTotal, 1600);
    expect(provider.sentCategories!.map((c) => c.mainCategory), contains('Shopping'));
  });

  testWidgets('raising a cap raises the total by the same amount', (tester) async {
    final provider = await _open(tester);
    // Caps 860 -> 2,060 (+1,200): 1,500 + 1,200 = 2,700.
    await _editCap(tester, 'Transportation', '1500');
    expect(find.text(r'$2,700.00'), findsOneWidget);
    await _saveScreen(tester);
    expect(provider.sentTotal, 2700);
  });

  testWidgets('the total never ends below the sum of the caps', (tester) async {
    // A stored total ($800) below its caps ($860) is left alone on open...
    final provider = await _open(tester, total: 800);
    expect(find.text('TOTAL CAP'), findsNothing);
    // ...but once the caps change, 800 + 100 = 900 would be below the new
    // $960 sum, so the total becomes the sum.
    await _editCap(tester, 'Transportation', '400');
    expect(find.text(r'$960.00'), findsOneWidget);
    await _saveScreen(tester);
    expect(provider.sentTotal, 960);
  });
}
