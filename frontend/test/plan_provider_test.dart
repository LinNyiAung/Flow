import 'dart:async';

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

PlanStatus _status({
  Plan plan = Plan.free,
  int chatRemaining = 3,
  Map<String, String> contact = const {'en': 'Message us on Viber', 'my': 'Viber ဖြင့် ဆက်သွယ်ပါ'},
  UpgradeRequest? upgradeRequest,
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
    upgradeRequest: upgradeRequest,
  );
}

UpgradeRequest _request(Plan plan, {String? note, DateTime? at}) =>
    UpgradeRequest(plan: plan, note: note, createdAt: at ?? DateTime.utc(2026, 11, 3, 9));

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

  group('Upgrade request state', () {
    test('GET /api/plan upgrade_request is parsed; none or a bad one is null', () {
      final withRequest = PlanStatus.fromJson({
        'plan': 'free',
        'upgrade_request': {'plan': 'plus', 'note': 'Please', 'created_at': '2026-11-03T09:00:00+00:00'},
      });
      expect(withRequest.upgradeRequest!.plan, Plan.plus);
      expect(withRequest.upgradeRequest!.note, 'Please');
      expect(withRequest.upgradeRequest!.createdAt.toUtc(), DateTime.utc(2026, 11, 3, 9));

      expect(PlanStatus.fromJson({'plan': 'free', 'upgrade_request': null}).upgradeRequest, isNull);
      expect(PlanStatus.fromJson({'plan': 'free'}).upgradeRequest, isNull);
      // A blank note is no note; an unknown plan or a missing date is no request.
      expect(
        PlanStatus.fromJson({
          'plan': 'free',
          'upgrade_request': {'plan': 'pro', 'note': '  ', 'created_at': '2026-11-03T09:00:00+00:00'},
        }).upgradeRequest!.note,
        isNull,
      );
      expect(
        PlanStatus.fromJson({
          'plan': 'free',
          'upgrade_request': {'plan': 'gold', 'created_at': '2026-11-03T09:00:00+00:00'},
        }).upgradeRequest,
        isNull,
      );
      expect(PlanStatus.fromJson({'plan': 'free', 'upgrade_request': {'plan': 'plus'}}).upgradeRequest, isNull);
    });

    test('requestablePlans: the paid plans above the user\'s own', () {
      expect(requestablePlans(Plan.free), [Plan.plus, Plan.pro]);
      expect(requestablePlans(Plan.plus), [Plan.pro]);
      expect(requestablePlans(Plan.pro), isEmpty);
      // A trial of Plus is not "already on Plus": see the trial test below.
    });

    test('a request shows in the status at once, and a request for the other plan replaces it', () async {
      final sent = <(Plan, String?)>[];
      final provider = PlanProvider(
        loader: () async => _status(),
        requester: (plan, note) async {
          sent.add((plan, note));
          return _request(plan, note: note);
        },
      );
      await provider.refresh();
      expect(provider.upgradeRequest, isNull);

      final first = await provider.requestUpgrade(Plan.plus, note: 'hello');
      expect(first.plan, Plan.plus);
      expect(provider.upgradeRequest!.plan, Plan.plus);
      expect(provider.upgradeRequest!.note, 'hello');
      expect(provider.status!.plan, Plan.free); // the rest of the status is untouched
      expect(provider.feature(PlanFeature.chat)!.remaining, 3);

      await provider.requestUpgrade(Plan.pro);
      expect(provider.upgradeRequest!.plan, Plan.pro);
      expect(provider.upgradeRequest!.note, isNull);
      expect(sent, [(Plan.plus, 'hello'), (Plan.pro, null)]);
      provider.dispose();
    });

    test('a refused request throws and leaves the status as it was', () async {
      final provider = PlanProvider(
        loader: () async => _status(upgradeRequest: _request(Plan.plus)),
        requester: (plan, note) async => throw ApiException('You\'re already on the Pro plan or a higher one.', statusCode: 400),
      );
      await provider.refresh();

      await expectLater(
        provider.requestUpgrade(Plan.pro),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('already'))),
      );

      expect(provider.upgradeRequest!.plan, Plan.plus);
      expect(provider.isRequestingUpgrade, isFalse);
      provider.dispose();
    });

    test('isRequestingUpgrade is true while it is sent, and a second tap joins the first', () async {
      final gate = Completer<UpgradeRequest>();
      var calls = 0;
      final provider = PlanProvider(
        loader: () async => _status(),
        requester: (plan, note) {
          calls++;
          return gate.future;
        },
      );
      await provider.refresh();

      final first = provider.requestUpgrade(Plan.plus);
      final second = provider.requestUpgrade(Plan.plus);
      expect(provider.isRequestingUpgrade, isTrue);
      gate.complete(_request(Plan.plus));
      await Future.wait([first, second]);

      expect(calls, 1);
      expect(provider.isRequestingUpgrade, isFalse);
      expect(provider.upgradeRequest!.plan, Plan.plus);
      provider.dispose();
    });

    test('reset drops the request, and a late answer for the old user is ignored', () async {
      final gate = Completer<UpgradeRequest>();
      final provider = PlanProvider(
        loader: () async => _status(),
        requester: (plan, note) => gate.future,
      );
      await provider.refresh();

      final inFlight = provider.requestUpgrade(Plan.plus);
      provider.reset(); // logout / another user
      gate.complete(_request(Plan.plus));
      await inFlight;
      expect(provider.status, isNull);
      expect(provider.isRequestingUpgrade, isFalse);

      // The next user's plan does not inherit it.
      await provider.refresh();
      expect(provider.upgradeRequest, isNull);
      provider.dispose();
    });
  });

  group('Upgrade screen', () {
    Future<void> openScreen(
      WidgetTester tester,
      PlanStatus status,
      Locale locale, {
      Future<UpgradeRequest> Function(Plan plan, String? note)? requester,
    }) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(
              create: (_) => PlanProvider(loader: () async => status, requester: requester),
            ),
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

    testWidgets('a Free user can ask for Plus: note dialog, then the card says when', (tester) async {
      final sent = <(Plan, String?)>[];
      await openScreen(
        tester,
        _status(),
        const Locale('en'),
        requester: (plan, note) async {
          sent.add((plan, note));
          return _request(plan, note: note, at: DateTime(2026, 11, 3, 12));
        },
      );

      expect(find.text('Request Plus'), findsOneWidget);
      expect(find.text('Request Pro'), findsOneWidget);
      expect(find.textContaining('Requested on'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('request-plus')));
      await tester.tap(find.byKey(const Key('request-plus')));
      await tester.pumpAndSettle();
      // The dialog: title, an optional note, Send.
      expect(find.byKey(const Key('upgrade-request-note')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('upgrade-request-note')), '  Please upgrade me  ');
      await tester.tap(find.byKey(const Key('upgrade-request-send')));
      await tester.pumpAndSettle();

      expect(sent, [(Plan.plus, 'Please upgrade me')]);
      expect(find.byKey(const Key('upgrade-requested-plus')), findsOneWidget);
      expect(find.text('Requested on 3 November 2026. We\'ll be in touch.'), findsOneWidget);
      expect(find.text('Request Plus'), findsNothing);
      expect(find.text('Request Pro'), findsOneWidget);

      // Asking for Pro moves the "requested" card to Pro.
      await tester.ensureVisible(find.byKey(const Key('request-pro')));
      await tester.tap(find.byKey(const Key('request-pro')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('upgrade-request-send')));
      await tester.pumpAndSettle();

      expect(sent.last, (Plan.pro, ''));
      expect(find.byKey(const Key('upgrade-requested-pro')), findsOneWidget);
      expect(find.byKey(const Key('upgrade-requested-plus')), findsNothing);
      expect(find.text('Request Plus'), findsOneWidget);
    });

    testWidgets('cancelling the dialog sends nothing; a refused request shows a snackbar', (tester) async {
      var calls = 0;
      await openScreen(
        tester,
        _status(),
        const Locale('en'),
        requester: (plan, note) async {
          calls++;
          throw ApiException('You\'re already on the Plus plan or a higher one.', statusCode: 400);
        },
      );

      await tester.ensureVisible(find.byKey(const Key('request-plus')));
      await tester.tap(find.byKey(const Key('request-plus')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byKey(const Key('request-plus')), findsOneWidget);

      await tester.tap(find.byKey(const Key('request-plus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('upgrade-request-send')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('You\'re already on the Plus plan or a higher one.'), findsOneWidget);
      expect(find.byKey(const Key('request-plus')), findsOneWidget); // nothing was recorded
    });

    testWidgets('the note limit counts code points like the server, so a Burmese note is not cut short', (tester) async {
      // 70 x 8 = 560 code points, but far fewer than 500 grapheme clusters: the
      // field's own maxLength (clusters) would let all of it through.
      final burmese = 'ကျွန်ုပ်' * 70;
      expect(burmese.characters.length, lessThan(500));
      expect(burmese.runes.length, greaterThan(500));
      expect(noteLength(burmese), 560);

      final sent = <(Plan, String?)>[];
      await openScreen(
        tester,
        _status(),
        const Locale('en'),
        requester: (plan, note) async {
          sent.add((plan, note));
          return _request(plan, note: note);
        },
      );
      await tester.ensureVisible(find.byKey(const Key('request-plus')));
      await tester.tap(find.byKey(const Key('request-plus')));
      await tester.pumpAndSettle();

      final send = find.byKey(const Key('upgrade-request-send'));
      bool sendEnabled() => tester.widget<FilledButton>(send).onPressed != null;
      Text counter() => tester.widget<Text>(find.byKey(const Key('upgrade-request-note-counter')));

      expect(counter().data, '0/500');
      expect(sendEnabled(), isTrue); // an empty note is fine

      await tester.enterText(find.byKey(const Key('upgrade-request-note')), burmese);
      await tester.pump();
      expect(counter().data, '560/500');
      expect(sendEnabled(), isFalse);
      expect(find.text('Your note is too long. Please shorten it.'), findsOneWidget);

      // 62 x 8 = 496 code points: fine.
      await tester.enterText(find.byKey(const Key('upgrade-request-note')), 'ကျွန်ုပ်' * 62);
      await tester.pump();
      expect(counter().data, '496/500');
      expect(sendEnabled(), isTrue);
      expect(find.text('Your note is too long. Please shorten it.'), findsNothing);

      // Exactly 500 is allowed, 501 is not (an emoji is one code point beyond the BMP pair: 1 rune, 2 UTF-16 units).
      await tester.enterText(find.byKey(const Key('upgrade-request-note')), 'a' * 500);
      await tester.pump();
      expect(counter().data, '500/500');
      expect(sendEnabled(), isTrue);
      await tester.enterText(find.byKey(const Key('upgrade-request-note')), '${'a' * 499}😀');
      await tester.pump();
      expect(counter().data, '500/500');
      expect(sendEnabled(), isTrue);
      await tester.enterText(find.byKey(const Key('upgrade-request-note')), 'a' * 501);
      await tester.pump();
      expect(sendEnabled(), isFalse);

      await tester.tap(send, warnIfMissed: false);
      await tester.pump();
      expect(sent, isEmpty); // Send is blocked
    });

    for (final (locale, expected) in const [
      (Locale('en'), 'Your note is too long. Please shorten it.'),
      (Locale('my'), 'သင့်မှတ်ချက် ရှည်လွန်းပါသည်။ ပိုတိုအောင် ရေးပေးပါ။'),
    ]) {
      testWidgets('a 422 from the server shows the "note is too long" text, not the server\'s (${locale.languageCode})',
          (tester) async {
        await openScreen(
          tester,
          _status(),
          locale,
          requester: (plan, note) async =>
              throw ApiException('Note must be at most 500 characters', statusCode: 422),
        );
        await tester.ensureVisible(find.byKey(const Key('request-plus')));
        await tester.tap(find.byKey(const Key('request-plus')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('upgrade-request-send')));
        await tester.pumpAndSettle();

        expect(find.text(expected), findsOneWidget);
        expect(find.textContaining('Note must be'), findsNothing);
      });
    }

    test('a user on the Plus trial can ask to keep Plus', () {
      expect(requestablePlans(Plan.plus, isTrial: true), [Plan.plus, Plan.pro]);
      expect(requestablePlans(Plan.plus), [Plan.pro]); // paid Plus: only Pro
      expect(requestablePlans(Plan.pro, isTrial: true), isEmpty);
    });

    testWidgets('the request texts are in Myanmar', (tester) async {
      await openScreen(
        tester,
        _status(upgradeRequest: _request(Plan.plus, at: DateTime(2026, 11, 3, 12))),
        const Locale('my'),
      );

      expect(find.byKey(const Key('upgrade-requested-plus')), findsOneWidget);
      expect(find.textContaining('တောင်းဆိုထားပါသည်'), findsOneWidget);
      expect(find.textContaining('3 နိုဝင်ဘာ 2026'), findsOneWidget); // Burmese month name
      expect(find.textContaining('Nov'), findsNothing);
      expect(find.byKey(const Key('request-pro')), findsOneWidget);
      expect(find.text('Request Pro'), findsNothing);
    });

    testWidgets('falls back to the generic contact text when the owner set none',
        (tester) async {
      await openScreen(tester, _status(contact: const {}), const Locale('en'));

      expect(find.byKey(const Key('upgrade-contact-message')), findsOneWidget);
      expect(find.text('Please contact Admin support to upgrade your plan.'), findsOneWidget);
    });
  });
}
