import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/subscription/subscription_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _family = {
  Plan.free: PlanFamilyLimits(maxMembers: 0, maxPlaceholders: 0),
  Plan.plus: PlanFamilyLimits(maxMembers: 6, maxPlaceholders: 20),
  Plan.pro: PlanFamilyLimits(maxMembers: 8, maxPlaceholders: 0),
};

PlanStatus _status({Map<Plan, PlanFamilyLimits> family = _family}) => PlanStatus(
      plan: Plan.free,
      catalog: const {
        Plan.free: {PlanFeature.chat: CatalogLimit(mode: 'counted', quota: 7, period: 'week')},
        Plan.plus: {PlanFeature.chat: CatalogLimit(mode: 'counted', quota: 123, period: 'month')},
        Plan.pro: {PlanFeature.chat: CatalogLimit(mode: 'counted', quota: 456, period: 'month')},
      },
      prices: const {Plan.plus: PlanPrice(monthlyMmk: 15000)},
      familyByPlan: family,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
  });

  group('family_by_plan from GET /api/plan', () {
    test('parsed per plan; unknown plans and unreadable rows are skipped', () {
      final status = PlanStatus.fromJson({
        'plan': 'free',
        'family_by_plan': {
          'free': {'max_members': 0, 'max_placeholders': 0},
          'plus': {'max_members': 6, 'max_placeholders': 20},
          'pro': {'max_members': '6', 'max_placeholders': 20},
          'gold': {'max_members': 9, 'max_placeholders': 9},
        },
      });
      expect(status.familyByPlan.keys, unorderedEquals([Plan.free, Plan.plus]));
      expect(status.familyByPlan[Plan.free]!.canCreate, isFalse);
      expect(status.familyByPlan[Plan.plus]!.maxMembers, 6);
      expect(status.familyByPlan[Plan.plus]!.maxPlaceholders, 20);
      expect(status.withUpgradeRequest(null).familyByPlan[Plan.plus]!.maxMembers, 6);
    });

    test('an older server sends none', () {
      expect(PlanStatus.fromJson({'plan': 'free'}).familyByPlan, isEmpty);
      expect(PlanStatus.fromJson({'plan': 'free', 'family_by_plan': 'x'}).familyByPlan, isEmpty);
    });
  });

  group('Family book row', () {
    Future<void> openScreen(WidgetTester tester, PlanStatus status, {Locale locale = const Locale('en')}) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PlanProvider(loader: () async => status)),
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

    Iterable<String> texts(WidgetTester tester, String key) => find
        .descendant(of: find.byKey(Key(key)), matching: find.byType(Text), matchRoot: true)
        .evaluate()
        .map((e) => (e.widget as Text).data!);

    testWidgets('Free can join; paid plans show people and names from the server', (tester) async {
      await openScreen(tester, _status());

      expect(find.text('Family book'), findsOneWidget);
      expect(texts(tester, 'plan-family-free'), ['Join']);
      expect(texts(tester, 'plan-family-plus'), ['6', 'people', '+20 names']);
      // No names allowed: no names line.
      expect(texts(tester, 'plan-family-pro'), ['8', 'people']);
      // Right after the Price row, before the first feature row.
      final family = tester.getTopLeft(find.text('Family book')).dy;
      expect(family, greaterThan(tester.getTopLeft(find.text('Price')).dy));
      expect(family, lessThan(tester.getTopLeft(find.text('Ko Toe Pwar chat')).dy));
    });

    testWidgets('no row from an older server', (tester) async {
      await openScreen(tester, _status(family: const {}));
      expect(find.text('Family book'), findsNothing);
      expect(find.byKey(const Key('plan-family-free')), findsNothing);
    });

    for (final locale in const [Locale('en'), Locale('my')]) {
      testWidgets('the row fits a narrow phone (${locale.languageCode})', (tester) async {
        tester.view.physicalSize = const Size(320 * 3, 800 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await openScreen(tester, _status(), locale: locale);

        expect(tester.takeException(), isNull);
        final table = tester.getRect(find.byKey(const Key('plan-comparison-table')));
        for (final plan in const ['free', 'plus', 'pro']) {
          final cell = tester.getRect(find.byKey(Key('plan-family-$plan')));
          expect(cell.right, lessThanOrEqualTo(table.right));
        }
        if (locale.languageCode == 'my') {
          expect(find.text('Family book'), findsNothing);
          expect(texts(tester, 'plan-family-plus').last, isNot('+20 names'));
        }
      });
    }
  });
}
