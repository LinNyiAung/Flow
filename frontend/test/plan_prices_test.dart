import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/subscription/subscription_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _plusPrice = PlanPrice(monthlyMmk: 15000, yearlyMmk: 150000);
const _proPrice = PlanPrice(monthlyMmk: 30000);

PlanStatus _status({Map<Plan, PlanPrice> prices = const {}}) => PlanStatus(
      plan: Plan.free,
      catalog: const {
        Plan.free: {PlanFeature.chat: CatalogLimit(mode: 'counted', quota: 7, period: 'week')},
        Plan.plus: {PlanFeature.chat: CatalogLimit(mode: 'counted', quota: 123, period: 'month')},
        Plan.pro: {PlanFeature.chat: CatalogLimit(mode: 'counted', quota: 456, period: 'month')},
      },
      prices: prices,
      upgradeContact: const {'en': 'Message us on Viber', 'my': 'Viber ဖြင့် ဆက်သွယ်ပါ'},
    );

Widget _app(Widget home, Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('my')],
      home: home,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
  });

  group('Prices from GET /api/plan', () {
    test('prices are parsed per plan', () {
      final status = PlanStatus.fromJson({
        'plan': 'free',
        'prices': {
          'free': {'monthly_mmk': null, 'yearly_mmk': null},
          'plus': {'monthly_mmk': 15000, 'yearly_mmk': 150000},
          'pro': {'monthly_mmk': 30000, 'yearly_mmk': null},
          'gold': {'monthly_mmk': 1, 'yearly_mmk': null},
        },
      });
      expect(status.priceOf(Plan.plus).monthlyMmk, 15000);
      expect(status.priceOf(Plan.plus).yearlyMmk, 150000);
      expect(status.priceOf(Plan.plus).hasYearly, isTrue);
      expect(status.priceOf(Plan.pro).monthlyMmk, 30000);
      expect(status.priceOf(Plan.pro).yearlyMmk, isNull);
      expect(status.priceOf(Plan.pro).hasYearly, isFalse);
      expect(status.priceOf(Plan.free).hasMonthly, isFalse);
      // A new request keeps the prices.
      expect(status.withUpgradeRequest(null).priceOf(Plan.plus).monthlyMmk, 15000);
    });

    test('an older server without prices (or unreadable values) means no price', () {
      final old = PlanStatus.fromJson({'plan': 'free'});
      for (final plan in Plan.values) {
        expect(old.priceOf(plan).hasMonthly, isFalse);
        expect(old.priceOf(plan).yearlyMmk, isNull);
      }
      expect(PlanStatus.fromJson({'plan': 'free', 'prices': 'x'}).priceOf(Plan.plus).hasMonthly, isFalse);
      expect(PlanStatus.fromJson({'plan': 'free', 'prices': {'plus': 5}}).priceOf(Plan.plus).hasMonthly, isFalse);
      expect(PlanPrice.fromJson({'monthly_mmk': 0}).hasMonthly, isFalse);
      expect(PlanPrice.fromJson({'monthly_mmk': -5}).hasMonthly, isFalse);
      expect(PlanPrice.fromJson({'monthly_mmk': '15000'}).hasMonthly, isFalse);
      // A yearly price without a monthly one is not shown.
      final yearlyOnly = PlanPrice.fromJson({'monthly_mmk': null, 'yearly_mmk': 150000});
      expect(yearlyOnly.hasYearly, isFalse);
      expect(yearlyOnly.yearlyMmk, isNull);
    });

    test('save % is 12 monthly payments against the yearly price, rounded', () {
      expect(_plusPrice.savePercent, 17); // 1 - 150000 / 180000 = 16.7%
      expect(const PlanPrice(monthlyMmk: 10000, yearlyMmk: 100000).savePercent, 17);
      expect(const PlanPrice(monthlyMmk: 10000, yearlyMmk: 60000).savePercent, 50);
      expect(const PlanPrice(monthlyMmk: 10000, yearlyMmk: 120000).savePercent, 0);
      expect(const PlanPrice(monthlyMmk: 10000, yearlyMmk: 130000).savePercent, -8);
      expect(_proPrice.savePercent, isNull);
      expect(PlanPrice.none.savePercent, isNull);
    });

    test('the pending request carries the billing period', () {
      UpgradeRequest? parse(dynamic billing) => UpgradeRequest.tryParse({
            'plan': 'plus',
            'billing': billing,
            'created_at': '2026-11-05T09:00:00+00:00',
          });
      expect(parse('month')!.billing, PlanBilling.month);
      expect(parse('year')!.billing, PlanBilling.year);
      expect(parse(null)!.billing, isNull);
      expect(parse('week')!.billing, isNull);
      expect(UpgradeRequest.tryParse({'plan': 'pro', 'created_at': '2026-11-05T09:00:00+00:00'})!.billing, isNull);
    });

    test('prices are written K and whole kyat with thousands separators', () {
      expect(formatPlanPrice(15000), 'K15,000');
      expect(formatPlanPrice(500), 'K500');
      expect(formatPlanPrice(1000000000), 'K1,000,000,000');
      final en = AppLocalizations(const Locale('en'));
      expect(upgradeYearlyText(en, _plusPrice), 'or K150,000 / year · save 17%');
      expect(upgradeYearlyText(en, const PlanPrice(monthlyMmk: 10000, yearlyMmk: 120000)), 'or K120,000 / year');
      expect(upgradeYearlyText(en, _proPrice), isNull);
    });
  });

  group('Upgrade screen with prices', () {
    Future<void> openScreen(
      WidgetTester tester,
      PlanStatus status, {
      Locale locale = const Locale('en'),
      Future<UpgradeRequest> Function(Plan plan, String? note, String? viber, String? billing)? requester,
    }) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PlanProvider(loader: () async => status, requester: requester)),
        ],
        child: _app(SubscriptionScreen(), locale),
      ));
      await tester.pumpAndSettle();
    }

    String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

    /// The billing choice shows the filled radio mark.
    bool picked(WidgetTester tester, String billing) => find
        .descendant(
          of: find.byKey(Key('upgrade-billing-$billing')),
          matching: find.byIcon(Icons.radio_button_checked_rounded),
        )
        .evaluate()
        .isNotEmpty;

    testWidgets('each upgrade card shows its price above the button', (tester) async {
      await openScreen(tester, _status(prices: {Plan.plus: _plusPrice, Plan.pro: _proPrice}));

      expect(text(tester, 'upgrade-price-plus'), 'K15,000 / month');
      expect(text(tester, 'upgrade-price-yearly-plus'), 'or K150,000 / year · save 17%');
      expect(text(tester, 'upgrade-price-pro'), 'K30,000 / month');
      expect(find.byKey(const Key('upgrade-price-yearly-pro')), findsNothing);
      // Above the button.
      expect(tester.getTopLeft(find.byKey(const Key('upgrade-price-plus'))).dy,
          lessThan(tester.getTopLeft(find.byKey(const Key('request-plus'))).dy));
    });

    testWidgets('no price set: no price anywhere, the table has no Price row', (tester) async {
      await openScreen(tester, _status());

      expect(find.byKey(const Key('upgrade-price-plus')), findsNothing);
      expect(find.byKey(const Key('upgrade-price-pro')), findsNothing);
      expect(find.text('Price'), findsNothing);
      expect(find.byKey(const Key('plan-price-free')), findsNothing);
      expect(find.textContaining(RegExp(r'K\d')), findsNothing);
      // The table is unchanged: one "per week" (Free chat), two "per month".
      expect(find.text('per week'), findsOneWidget);
      expect(find.text('per month'), findsNWidgets(2));
    });

    testWidgets('a Free price is never shown, even if the server sent one', (tester) async {
      await openScreen(tester, _status(prices: {Plan.free: const PlanPrice(monthlyMmk: 999)}));
      expect(find.text('Price'), findsNothing);
      expect(find.textContaining('K999'), findsNothing);
    });

    testWidgets('the table starts with a Price row: Free, the monthly price, or a dash', (tester) async {
      await openScreen(tester, _status(prices: {Plan.plus: _plusPrice}));

      expect(find.text('Price'), findsOneWidget);
      expect(text(tester, 'plan-price-free'), 'Free');
      expect(text(tester, 'plan-price-plus'), 'K15,000');
      expect(find.byKey(const Key('plan-price-pro')), findsNothing); // Pro has no price: the dash
      // The Price row comes before the first feature row.
      expect(tester.getTopLeft(find.text('Price')).dy, lessThan(tester.getTopLeft(find.text('AI chat')).dy));
      // Its period uses the table's own "per month" (Plus price + Plus and Pro chat).
      expect(find.text('per month'), findsNWidgets(3));
    });

    for (final locale in const [Locale('en'), Locale('my')]) {
      testWidgets('the Price row fits a narrow phone (${locale.languageCode})', (tester) async {
        tester.view.physicalSize = const Size(320 * 3, 800 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await openScreen(
          tester,
          _status(prices: {
            Plan.plus: const PlanPrice(monthlyMmk: 999999999, yearlyMmk: 1000000000),
            Plan.pro: const PlanPrice(monthlyMmk: 1000000000),
          }),
          locale: locale,
        );

        expect(tester.takeException(), isNull);
        final table = tester.getSize(find.byKey(const Key('plan-comparison-table')));
        expect(table.width, lessThanOrEqualTo(320));
        // The price is shrunk to its column, not cut or wrapped.
        final price = tester.getRect(find.byKey(const Key('plan-price-pro')));
        final tableRect = tester.getRect(find.byKey(const Key('plan-comparison-table')));
        expect(price.right, lessThanOrEqualTo(tableRect.right));
        expect(text(tester, 'plan-price-pro'), 'K1,000,000,000');
      });
    }

    testWidgets('the dialog asks monthly or yearly and sends the choice as billing', (tester) async {
      final sent = <(Plan, String?)>[];
      await openScreen(
        tester,
        _status(prices: {Plan.plus: _plusPrice, Plan.pro: _proPrice}),
        requester: (plan, note, viber, billing) async {
          sent.add((plan, billing));
          return UpgradeRequest(plan: plan, billing: billing, createdAt: DateTime.utc(2026, 11, 5, 9));
        },
      );

      await tester.ensureVisible(find.byKey(const Key('request-plus')));
      await tester.tap(find.byKey(const Key('request-plus')));
      await tester.pumpAndSettle();
      expect(find.text('Monthly · K15,000'), findsOneWidget);
      expect(find.text('Yearly · K150,000 · save 17%'), findsOneWidget);
      // Monthly is picked by default; the rest of the dialog is as before.
      expect(picked(tester, 'month'), isTrue);
      expect(picked(tester, 'year'), isFalse);
      expect(find.byKey(const Key('upgrade-request-viber')), findsOneWidget);
      expect(find.byKey(const Key('upgrade-request-note')), findsOneWidget);
      await tester.tap(find.byKey(const Key('upgrade-billing-year')));
      await tester.pump();
      expect(picked(tester, 'year'), isTrue);
      expect(picked(tester, 'month'), isFalse);
      await tester.tap(find.byKey(const Key('upgrade-request-send')));
      await tester.pumpAndSettle();
      expect(sent.last, (Plan.plus, PlanBilling.year));

      // Pro has only a monthly price: no Yearly choice, Monthly goes with the request.
      await tester.ensureVisible(find.byKey(const Key('request-pro')));
      await tester.tap(find.byKey(const Key('request-pro')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('upgrade-billing-month')), findsOneWidget);
      expect(find.byKey(const Key('upgrade-billing-year')), findsNothing);
      expect(find.text('Monthly · K30,000'), findsOneWidget);
      await tester.tap(find.byKey(const Key('upgrade-request-send')));
      await tester.pumpAndSettle();
      expect(sent.last, (Plan.pro, PlanBilling.month));
    });

    testWidgets('without a price there is no choice and no billing is sent', (tester) async {
      final sent = <(Plan, String?)>[];
      await openScreen(
        tester,
        _status(prices: {Plan.pro: _proPrice}),
        requester: (plan, note, viber, billing) async {
          sent.add((plan, billing));
          return UpgradeRequest(plan: plan, createdAt: DateTime.utc(2026, 11, 5, 9));
        },
      );
      await tester.ensureVisible(find.byKey(const Key('request-plus')));
      await tester.tap(find.byKey(const Key('request-plus')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('upgrade-billing-month')), findsNothing);
      expect(find.byKey(const Key('upgrade-billing-year')), findsNothing);
      expect(find.text('How would you like to pay?'), findsNothing);
      await tester.tap(find.byKey(const Key('upgrade-request-send')));
      await tester.pumpAndSettle();
      expect(sent, [(Plan.plus, null)]);
    });

    testWidgets('a yearly price that saves nothing shows no "save"', (tester) async {
      await openScreen(tester, _status(prices: {Plan.plus: const PlanPrice(monthlyMmk: 10000, yearlyMmk: 120000)}));
      expect(text(tester, 'upgrade-price-yearly-plus'), 'or K120,000 / year');
      await tester.ensureVisible(find.byKey(const Key('request-plus')));
      await tester.tap(find.byKey(const Key('request-plus')));
      await tester.pumpAndSettle();
      expect(find.text('Yearly · K120,000'), findsOneWidget);
      expect(find.textContaining(RegExp(r'save \d')), findsNothing);
    });

    testWidgets('a price that changed meanwhile (422 billing) says so in the app language', (tester) async {
      await openScreen(
        tester,
        _status(prices: {Plan.plus: _plusPrice}),
        locale: const Locale('my'),
        requester: (plan, note, viber, billing) async =>
            throw ApiException('billing: the Plus plan has no yearly price', statusCode: 422),
      );
      await tester.ensureVisible(find.byKey(const Key('request-plus')));
      await tester.tap(find.byKey(const Key('request-plus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('upgrade-billing-year')));
      await tester.tap(find.byKey(const Key('upgrade-request-send')));
      await tester.pumpAndSettle();
      expect(find.text(AppLocalizations(const Locale('my')).upgradeRequestPriceChanged), findsOneWidget);
      expect(find.textContaining('billing'), findsNothing);
    });

    testWidgets('the prices and the choice read in Myanmar', (tester) async {
      await openScreen(tester, _status(prices: {Plan.plus: _plusPrice}), locale: const Locale('my'));
      expect(text(tester, 'upgrade-price-plus'), 'K15,000 / တစ်လ');
      expect(text(tester, 'upgrade-price-yearly-plus'), 'သို့မဟုတ် K150,000 / တစ်နှစ် · 17% သက်သာ');
      expect(find.text('စျေးနှုန်း'), findsOneWidget);
      expect(text(tester, 'plan-price-free'), 'အခမဲ့');
      await tester.ensureVisible(find.byKey(const Key('request-plus')));
      await tester.tap(find.byKey(const Key('request-plus')));
      await tester.pumpAndSettle();
      expect(find.text('လစဉ် · K15,000'), findsOneWidget);
      expect(find.text('နှစ်စဉ် · K150,000 · 17% သက်သာ'), findsOneWidget);
    });
  });

  test('the price strings exist in English and Myanmar', () {
    const en = Locale('en');
    const my = Locale('my');
    final getters = <String Function(AppLocalizations)>[
      (l) => l.planPriceRow,
      (l) => l.planPriceFree,
      (l) => l.planPriceMonthly('K1'),
      (l) => l.planPriceYearlyOr('K1'),
      (l) => l.planPriceSave(17),
      (l) => l.upgradeBillingLabel,
      (l) => l.upgradeBillingMonthly('K1'),
      (l) => l.upgradeBillingYearly('K1'),
      (l) => l.upgradeRequestPriceChanged,
    ];
    final myanmar = RegExp('[က-႟]');
    for (final get in getters) {
      final english = get(AppLocalizations(en));
      final burmese = get(AppLocalizations(my));
      // A missing translation falls back to the camelCase key itself.
      final key = RegExp(r'^[a-z]+[A-Z]');
      expect(key.hasMatch(english), isFalse, reason: 'EN missing: $english');
      expect(key.hasMatch(burmese), isFalse, reason: 'MY missing: $burmese');
      expect(english.contains('{') || burmese.contains('{'), isFalse);
      expect(myanmar.hasMatch(burmese), isTrue, reason: 'not translated: $burmese');
      expect(burmese, isNot(english));
    }
  });
}
