import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/transactions/add_transaction_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 720x1280 @ 2.0 dpr = 360x640 logical, with status + nav bar insets.
  testWidgets('small phone: amount, type toggle and first keypad row visible',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 96);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ],
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: const [Locale('en'), Locale('my')],
          home: AddTransactionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const screenHeight = 640.0;
    const bottomInset = 48.0;
    final l = AppLocalizations(const Locale('en'));

    double top(Finder f) => tester.getTopLeft(f).dy;
    double bottom(Finder f) => tester.getBottomLeft(f).dy;

    final toggle = find.text(l.outflow);
    final amount = find.text('0');
    final key1 = find.text('1');
    final key0 = find.text('0').last;

    // Header (type toggle + amount) stays below the app bar.
    expect(top(toggle), greaterThanOrEqualTo(24 + 56 - 1));
    expect(top(amount.first), greaterThanOrEqualTo(24 + 56));
    // First keypad row revealed above the nav bar.
    expect(bottom(key1), lessThanOrEqualTo(screenHeight - bottomInset));

    // Tapping the amount reveals the whole keypad; the amount stays visible.
    await tester.tap(amount.first);
    await tester.pumpAndSettle();
    expect(bottom(key0), lessThanOrEqualTo(screenHeight - bottomInset));
    expect(top(amount.first), greaterThanOrEqualTo(24 + 56));
    expect(top(toggle), greaterThanOrEqualTo(24 + 56 - 1));
  });
}
