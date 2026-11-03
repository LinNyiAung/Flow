import 'dart:async';

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

PlanStatus _status({
  Plan plan = Plan.free,
  int chatRemaining = 3,
  Map<String, String> contact = const {'en': 'Message us on Viber', 'my': 'Viber ဖြင့် ဆက်သွယ်ပါ'},
}) {
  FeatureAllowance counted(int limit, int remaining, String period) =>
      FeatureAllowance(
        mode: 'counted',
        limit: limit,
        used: limit - remaining,
        remaining: remaining,
        period: period,
      );
  Map<String, CatalogLimit> limits(Map<String, CatalogLimit> m) => m;
  const locked = CatalogLimit(mode: 'locked');
  const included = CatalogLimit(mode: 'included');
  return PlanStatus(
    plan: plan,
    features: {
      PlanFeature.chat: counted(5, chatRemaining, 'week'),
      PlanFeature.insightWeekly: const FeatureAllowance(mode: 'locked'),
    },
    catalog: {
      Plan.free: limits({
        PlanFeature.chat: const CatalogLimit(mode: 'counted', quota: 7, period: 'week'),
        PlanFeature.chatAdvanced: locked,
        PlanFeature.insightWeekly: locked,
        PlanFeature.reports: locked,
      }),
      Plan.plus: limits({
        PlanFeature.chat: const CatalogLimit(mode: 'counted', quota: 123, period: 'month'),
        PlanFeature.chatAdvanced: locked,
        PlanFeature.insightWeekly: included,
        PlanFeature.reports: included,
      }),
      Plan.pro: limits({
        PlanFeature.chat: const CatalogLimit(mode: 'counted', quota: 456, period: 'month'),
        PlanFeature.chatAdvanced: const CatalogLimit(mode: 'counted', quota: 77, period: 'month'),
        PlanFeature.insightWeekly: included,
        PlanFeature.reports: included,
      }),
    },
    upgradeContact: contact,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
  });

  group('PlanProvider', () {
    test('refresh loads the plan and exposes each feature', () async {
      final provider = PlanProvider(loader: () async => _status());
      expect(provider.status, isNull);

      await provider.refresh();

      expect(provider.status!.plan, Plan.free);
      expect(provider.feature(PlanFeature.chat)!.remaining, 3);
      expect(provider.error, isNull);
      expect(provider.isLoading, isFalse);
      provider.dispose();
    });

    test('isLocked follows the plan, and falls back while it is unknown', () async {
      final provider = PlanProvider(loader: () async => _status());
      expect(provider.isLocked(PlanFeature.insightWeekly), isFalse);
      expect(provider.isLocked(PlanFeature.insightWeekly, whenUnknown: true), isTrue);

      await provider.refresh();

      expect(provider.isLocked(PlanFeature.insightWeekly, whenUnknown: false), isTrue);
      expect(provider.isLocked(PlanFeature.chat, whenUnknown: true), isFalse);
      // A feature the server did not list is "unknown" too.
      expect(provider.isLocked(PlanFeature.reports, whenUnknown: true), isTrue);
      provider.dispose();
    });

    test('a failed refresh keeps the numbers already on screen', () async {
      final printer = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = printer);
      var fail = false;
      final provider = PlanProvider(loader: () async {
        if (fail) throw Exception('offline');
        return _status();
      });
      await provider.refresh();

      fail = true;
      await provider.refresh();

      expect(provider.status, isNotNull);
      expect(provider.error, 'offline');
      provider.dispose();
    });

    test('a refresh asked for during a refresh runs once more afterwards', () async {
      var loads = 0;
      final gate = Completer<void>();
      final provider = PlanProvider(loader: () async {
        loads++;
        if (loads == 1) await gate.future;
        return _status(chatRemaining: loads == 1 ? 3 : 2);
      });

      final first = provider.refresh();
      await Future<void>.delayed(Duration.zero);
      // Several AI actions finish while the first load is in flight.
      unawaited(provider.refresh());
      unawaited(provider.refresh());
      gate.complete();
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(loads, 2); // one extra load, not one per request
      expect(provider.feature(PlanFeature.chat)!.remaining, 2);
      provider.dispose();
    });

    test('reset drops the plan, and a late answer for the old user is ignored', () async {
      final gate = Completer<PlanStatus>();
      final provider = PlanProvider(loader: () => gate.future);

      final inFlight = provider.refresh();
      await Future<void>.delayed(Duration.zero);
      provider.reset(); // logout / another user
      gate.complete(_status(plan: Plan.pro));
      await inFlight;

      expect(provider.status, isNull);
      expect(provider.isLoading, isFalse);
      provider.dispose();
    });

    test('nothing is loaded when nobody is signed in', () async {
      SharedPreferences.setMockInitialValues({});
      var loads = 0;
      final provider = PlanProvider(loader: () async {
        loads++;
        return _status();
      });

      await provider.refresh();

      expect(loads, 0);
      expect(provider.status, isNull);
      provider.dispose();
    });
  });

  group('Upgrade screen', () {
    Future<void> openScreen(WidgetTester tester, PlanStatus status, Locale locale) async {
      await tester.pumpWidget(
        MultiProvider(
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
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('compares the plans from the server limits and marks the current one',
        (tester) async {
      await openScreen(tester, _status(), const Locale('en'));

      expect(find.byKey(const Key('plan-comparison-table')), findsOneWidget);
      // The numbers come from the catalog, not from the app.
      expect(find.text('7'), findsOneWidget);
      expect(find.text('123'), findsOneWidget);
      expect(find.text('456'), findsOneWidget);
      expect(find.text('77'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Plus'), findsOneWidget);
      expect(find.text('Pro'), findsOneWidget);
      // The signed-out test user is on Free: exactly one column is marked.
      expect(find.byKey(const Key('current-plan-marker')), findsOneWidget);
      expect(find.text('Current plan'), findsOneWidget);
      // Free has a quota per week, Plus and Pro per month.
      expect(find.text('per week'), findsOneWidget);
      expect(find.text('per month'), findsNWidgets(3));
    });

    testWidgets('shows the upgrade contact message in the app language', (tester) async {
      await openScreen(tester, _status(), const Locale('en'));
      expect(find.text('Message us on Viber'), findsOneWidget);
      expect(find.text('Viber ဖြင့် ဆက်သွယ်ပါ'), findsNothing);

      await openScreen(tester, _status(), const Locale('my'));
      expect(find.text('Viber ဖြင့် ဆက်သွယ်ပါ'), findsOneWidget);
      expect(find.text('Message us on Viber'), findsNothing);
    });

    for (final locale in const [Locale('en'), Locale('my')]) {
      testWidgets('fits a narrow phone with every feature row (${locale.languageCode})',
          (tester) async {
        tester.view.physicalSize = const Size(320 * 3, 800 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        Map<String, dynamic> counted(int q, String p) =>
            {'mode': 'counted', 'quota': q, 'period': p};
        const locked = {'mode': 'locked', 'quota': null, 'period': null};
        const included = {'mode': 'included', 'quota': null, 'period': null};
        final status = PlanStatus.fromJson({
          'plan': 'plus',
          'catalog': {
            'free': {
              'chat': counted(5, 'week'),
              'chat_advanced': locked,
              'insight_monthly': counted(1, 'month'),
              'insight_weekly': locked,
              'insight_translation': locked,
              'entry': counted(10, 'month'),
              'budget_suggestion': counted(1, 'month'),
              'reports': locked,
            },
            'plus': {
              'chat': counted(100, 'month'),
              'chat_advanced': locked,
              'insight_monthly': included,
              'insight_weekly': included,
              'insight_translation': included,
              'entry': counted(150, 'month'),
              'budget_suggestion': counted(5, 'month'),
              'reports': included,
            },
            'pro': {
              'chat': counted(400, 'month'),
              'chat_advanced': counted(100, 'month'),
              'insight_monthly': included,
              'insight_weekly': included,
              'insight_translation': included,
              'entry': counted(500, 'month'),
              'budget_suggestion': counted(20, 'month'),
              'reports': included,
            },
          },
          'upgrade_contact': {'en': 'Message us on Viber', 'my': 'Viber ဖြင့် ဆက်သွယ်ပါ'},
        });

        await openScreen(tester, status, locale);

        // No overflow errors were raised while laying out the table.
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('plan-comparison-table')), findsOneWidget);
        expect(find.text('500'), findsOneWidget);
        final table = tester.getSize(find.byKey(const Key('plan-comparison-table')));
        expect(table.width, lessThanOrEqualTo(320));
      });
    }

    testWidgets('falls back to the generic contact text when the owner set none',
        (tester) async {
      await openScreen(tester, _status(contact: const {}), const Locale('en'));

      expect(find.byKey(const Key('upgrade-contact-message')), findsOneWidget);
      expect(find.text('Please contact Admin support to upgrade your plan.'), findsOneWidget);
    });
  });
}
