import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/subscription/subscription_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/accepted_payments.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlanStatus _status() => PlanStatus(
      plan: Plan.free,
      catalog: const {
        Plan.free: {PlanFeature.chat: CatalogLimit(mode: 'counted', quota: 7, period: 'week')},
        Plan.plus: {PlanFeature.chat: CatalogLimit(mode: 'counted', quota: 123, period: 'month')},
        Plan.pro: {PlanFeature.chat: CatalogLimit(mode: 'counted', quota: 456, period: 'month')},
      },
      prices: const {Plan.plus: PlanPrice(monthlyMmk: 15000)},
      upgradeContact: const {'en': 'Message us on Viber', 'my': 'Viber ဖြင့် ဆက်သွယ်ပါ'},
    );

Future<void> _openScreen(WidgetTester tester, {Locale locale = const Locale('en')}) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => PlanProvider(loader: () async => _status())),
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
      home: SubscriptionScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

final _row = find.byKey(const Key('accepted-payments'));

/// Both methods' logo and name inside [scope].
void _expectBothMethods(Finder scope) {
  for (final (id, name) in const [('kpay', 'KPay'), ('wavepay', 'WavePay')]) {
    final method = find.descendant(of: scope, matching: find.byKey(Key('accepted-payment-$id')));
    expect(method, findsOneWidget, reason: id);
    expect(find.descendant(of: method, matching: find.text(name)), findsOneWidget, reason: name);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
  });

  test('the logos are bundled assets', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final method in acceptedPaymentMethods) {
      final data = await rootBundle.load(method.logoAsset);
      expect(data.lengthInBytes, greaterThan(0), reason: method.logoAsset);
    }
  });

  testWidgets('the Upgrade screen says "We accept" KPay and WavePay under the upgrade buttons', (tester) async {
    await _openScreen(tester);

    expect(_row, findsOneWidget);
    expect(find.descendant(of: _row, matching: find.text('We accept')), findsOneWidget);
    _expectBothMethods(_row);
    // Below the last upgrade button, above the contact box.
    final rowTop = tester.getTopLeft(_row).dy;
    expect(rowTop, greaterThan(tester.getBottomLeft(find.byKey(const Key('request-pro'))).dy));
    expect(rowTop, lessThan(tester.getTopLeft(find.byKey(const Key('upgrade-contact-message'))).dy));
    // Nothing to tap: it only informs.
    expect(find.descendant(of: _row, matching: find.byType(InkWell)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Myanmar the heading is translated and the brand names stay in Latin letters', (tester) async {
    await _openScreen(tester, locale: const Locale('my'));

    expect(find.descendant(of: _row, matching: find.text('လက်ခံသော ငွေပေးချေမှု')), findsOneWidget);
    _expectBothMethods(_row);
  });

  testWidgets('a screen reader hears one sentence for the row', (tester) async {
    final semantics = tester.ensureSemantics();
    await _openScreen(tester);

    expect(tester.getSemantics(_row).label, 'We accept KPay and WavePay');
    semantics.dispose();
  });

  testWidgets('the upgrade request dialog shows it last, above Send', (tester) async {
    await _openScreen(tester);
    await tester.ensureVisible(find.byKey(const Key('request-plus')));
    await tester.tap(find.byKey(const Key('request-plus')));
    await tester.pumpAndSettle();

    final inDialog = find.descendant(of: find.byType(AlertDialog), matching: _row);
    expect(inDialog, findsOneWidget);
    _expectBothMethods(inDialog);
    // The dialog's content scrolls on a small screen; once scrolled to, it sits above the buttons.
    await tester.ensureVisible(inDialog);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(inDialog).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('upgrade-request-send'))).dy));
    expect(tester.getTopLeft(inDialog).dy,
        greaterThan(tester.getBottomLeft(find.byKey(const Key('upgrade-request-note'))).dy));
  });
}
