import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/models/voice_image_models.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/plan_limit_sheet.dart';
import 'package:frontend/widgets/plan_usage_line.dart';
import 'package:http/http.dart' as http;

/// A `GET /api/plan` body for a Free user.
Map<String, dynamic> _freePlanJson() => {
      'plan': 'free',
      'expires_at': null,
      'is_trial': false,
      'trial_ends_at': null,
      'features': {
        'chat': {
          'mode': 'counted',
          'limit': 5,
          'period': 'week',
          'used': 2,
          'remaining': 3,
          'resets_at': '2026-11-09T17:30:00+00:00',
        },
        'chat_advanced': {
          'mode': 'locked',
          'limit': null,
          'period': null,
          'used': null,
          'remaining': null,
          'resets_at': null,
        },
        'insight_weekly': {
          'mode': 'locked',
          'limit': null,
          'period': null,
          'used': null,
          'remaining': null,
          'resets_at': null,
        },
        'insight_translation': {
          'mode': 'included',
          'limit': null,
          'period': null,
          'used': null,
          'remaining': null,
          'resets_at': null,
        },
        'entry': {
          'mode': 'counted',
          'limit': 10,
          'period': 'month',
          'used': 4,
          'remaining': 6,
          'resets_at': '2026-11-30T17:30:00+00:00',
        },
      },
      'catalog': {
        'free': {
          'chat': {'mode': 'counted', 'quota': 5, 'period': 'week'},
          'reports': {'mode': 'locked', 'quota': null, 'period': null},
        },
        'plus': {
          'chat': {'mode': 'counted', 'quota': 100, 'period': 'month'},
          'reports': {'mode': 'included', 'quota': null, 'period': null},
        },
        'pro': {
          'chat': {'mode': 'counted', 'quota': 400, 'period': 'month'},
          'chat_advanced': {'mode': 'counted', 'quota': 100, 'period': 'month'},
        },
        'premium': {
          'chat': {'mode': 'counted', 'quota': 1, 'period': 'month'},
        },
      },
      'upgrade_contact': {'en': 'Message us on Viber', 'my': 'Viber á€–á€¼á€„á€·á€º á€†á€€á€ºá€žá€½á€šá€ºá€•á€«'},
    };

String _planErrorBody({
  String code = 'plan_limit_reached',
  String? feature = 'chat',
  String? resetsAt = '2026-11-09T17:30:00+00:00',
  bool upgradeAvailable = true,
  String message = "You've reached your limit for AI chat. It resets on Nov 10, 2026.",
}) =>
    jsonEncode({
      'detail': {
        'code': code,
        'feature': feature,
        'resets_at': resetsAt,
        'upgrade_available': upgradeAvailable,
        'message': message,
      },
    });

void main() {
  group('PlanStatus.fromJson', () {
    test('plan_status_parses_counts', () {
      final status = PlanStatus.fromJson(_freePlanJson());

      expect(status.plan, Plan.free);
      expect(status.isPaid, isFalse);
      expect(status.isTrial, isFalse);
      expect(status.expiresAt, isNull);

      final chat = status.feature(PlanFeature.chat)!;
      expect(chat.isCounted, isTrue);
      expect(chat.limit, 5);
      expect(chat.used, 2);
      expect(chat.remaining, 3);
      expect(chat.period, 'week');
      expect(chat.resetsAt!.toUtc(), DateTime.utc(2026, 11, 9, 17, 30));

      final entry = status.feature(PlanFeature.entry)!;
      expect([entry.limit, entry.used, entry.remaining, entry.period],
          [10, 4, 6, 'month']);
    });

    test('locked and included features carry no counts', () {
      final status = PlanStatus.fromJson(_freePlanJson());

      final locked = status.feature(PlanFeature.insightWeekly)!;
      expect(locked.isLocked, isTrue);
      expect(locked.isCounted, isFalse);
      expect([locked.limit, locked.used, locked.remaining, locked.resetsAt],
          [null, null, null, null]);

      final included = status.feature(PlanFeature.insightTranslation)!;
      expect(included.isIncluded, isTrue);
      expect(included.remaining, isNull);
      expect(status.feature(PlanFeature.budgetSuggestion), isNull);
    });

    test('catalog is keyed by plan and unknown plans are skipped', () {
      final status = PlanStatus.fromJson(_freePlanJson());

      expect(status.catalog.keys, containsAll([Plan.free, Plan.plus, Plan.pro]));
      expect(status.catalog.length, 3); // the stray "premium" entry is ignored
      final plusChat = status.catalog[Plan.plus]![PlanFeature.chat]!;
      expect([plusChat.mode, plusChat.quota, plusChat.period],
          ['counted', 100, 'month']);
      expect(status.catalog[Plan.plus]![PlanFeature.reports]!.isIncluded, isTrue);
      expect(status.catalog[Plan.free]![PlanFeature.reports]!.isLocked, isTrue);
      expect(status.catalog[Plan.pro]![PlanFeature.chatAdvanced]!.quota, 100);
    });

    test('trial and expiry are parsed for a paid plan', () {
      final json = _freePlanJson()
        ..['plan'] = 'plus'
        ..['is_trial'] = true
        ..['trial_ends_at'] = '2026-12-01T00:00:00+00:00'
        ..['expires_at'] = '2026-12-01T00:00:00+00:00';
      final status = PlanStatus.fromJson(json);

      expect(status.plan, Plan.plus);
      expect(status.isPaid, isTrue);
      expect(status.isPro, isFalse);
      expect(status.isTrial, isTrue);
      expect(status.trialEndsAt!.toUtc(), DateTime.utc(2026, 12, 1));
      expect(status.expiresAt!.toUtc(), DateTime.utc(2026, 12, 1));
    });

    test('an unknown plan name counts as free', () {
      expect(PlanStatus.fromJson({'plan': 'premium'}).plan, Plan.free);
      expect(PlanStatus.fromJson({}).plan, Plan.free);
    });

    test('contact message follows the language and falls back to English', () {
      final status = PlanStatus.fromJson(_freePlanJson());
      expect(status.contactMessage('en'), 'Message us on Viber');
      expect(status.contactMessage('my'), 'Viber á€–á€¼á€„á€·á€º á€†á€€á€ºá€žá€½á€šá€ºá€•á€«');

      final noMy = PlanStatus.fromJson(
          {'upgrade_contact': {'en': 'Email us', 'my': '  '}});
      expect(noMy.contactMessage('my'), 'Email us');
      expect(PlanStatus.fromJson({}).contactMessage('en'), '');
    });
  });

  group('remaining count', () {
    test('remaining_never_negative_display', () {
      // The owner lowered Free chat from 5 to 3 after 4 uses.
      final lowered = FeatureAllowance.fromJson({
        'mode': 'counted',
        'limit': 3,
        'period': 'week',
        'used': 4,
        'remaining': -1,
      });
      expect(lowered.remaining, 0);
      expect(lowered.isExhausted, isTrue);

      // No "remaining" at all: worked out from limit and used, still >= 0.
      final derived = FeatureAllowance.fromJson(
          {'mode': 'counted', 'limit': 3, 'period': 'week', 'used': 4});
      expect(derived.remaining, 0);

      final en = AppLocalizations(const Locale('en'));
      expect(planUsageText(en, lowered), '0 of 3 left this week');
    });

    test('usage text names the period and never exceeds the limit', () {
      final en = AppLocalizations(const Locale('en'));
      final week = FeatureAllowance.fromJson(
          {'mode': 'counted', 'limit': 5, 'period': 'week', 'used': 2, 'remaining': 3});
      final month = FeatureAllowance.fromJson(
          {'mode': 'counted', 'limit': 150, 'period': 'month', 'used': 1, 'remaining': 149});
      final over = FeatureAllowance.fromJson(
          {'mode': 'counted', 'limit': 5, 'period': 'month', 'used': 0, 'remaining': 9});

      expect(planUsageText(en, week), '3 of 5 left this week');
      expect(planUsageText(en, month), '149 of 150 left this month');
      expect(planUsageText(en, over), '5 of 5 left this month');
    });

    test('locked, included and unknown allowances show no usage line', () {
      final en = AppLocalizations(const Locale('en'));
      expect(planUsageText(en, null), isNull);
      expect(planUsageText(en, const FeatureAllowance(mode: 'locked')), isNull);
      expect(planUsageText(en, const FeatureAllowance(mode: 'included')), isNull);
    });
  });

  group('PlanLimitException', () {
    test('limit_exception_from_429', () {
      final e = PlanLimitException.tryParse(429, _planErrorBody())!;

      expect(e.code, PlanLimitException.codeLimitReached);
      expect(e.isLimitReached, isTrue);
      expect(e.isLocked, isFalse);
      expect(e.statusCode, 429);
      expect(e.feature, 'chat');
      expect(e.resetsAt!.toUtc(), DateTime.utc(2026, 11, 9, 17, 30));
      expect(e.upgradeAvailable, isTrue);
      expect(e.message, contains('AI chat'));
      // The message is what the user sees; no "Exception:" noise.
      expect(e.toString(), 'Exception: ${e.message}');
    });

    test('locked feature (403) without a feature or reset date', () {
      final e = PlanLimitException.tryParse(
        403,
        _planErrorBody(
          code: 'plan_feature_locked',
          feature: null,
          resetsAt: null,
          upgradeAvailable: false,
          message: 'Only on Plus and Pro.',
        ),
      )!;

      expect(e.isLocked, isTrue);
      expect(e.statusCode, 403);
      expect(e.feature, isNull);
      expect(e.resetsAt, isNull);
      expect(e.upgradeAvailable, isFalse);
    });

    test('cost cap (429)', () {
      final e = PlanLimitException.tryParse(
          429, _planErrorBody(code: 'plan_cost_cap', feature: null))!;
      expect(e.isCostCap, isTrue);
      expect(e.feature, isNull);
    });

    test('the code decides, not the message', () {
      // Same code, empty message: still a limit error.
      final e = PlanLimitException.tryParse(429, _planErrorBody(message: ''))!;
      expect(e.isLimitReached, isTrue);
      expect(e.message, '');
      // Plan-sounding message, unknown code: not a plan error.
      expect(
        PlanLimitException.tryParse(
            429, _planErrorBody(code: 'something_else', message: 'plan limit reached')),
        isNull,
      );
    });

    test('other 403 / 429 / non-JSON bodies are not plan errors', () {
      expect(PlanLimitException.tryParse(403, '{"detail":"Email not verified"}'), isNull);
      expect(PlanLimitException.tryParse(429, '{"detail":"Too many requests"}'), isNull);
      expect(PlanLimitException.tryParse(403, '<html>Forbidden</html>'), isNull);
      expect(PlanLimitException.tryParse(500, _planErrorBody()), isNull);
      expect(PlanLimitException.tryParse(429, '[]'), isNull);
    });

    test('apiError turns a plan response into a PlanLimitException', () {
      final error = ApiService.apiError(
        http.Response(_planErrorBody(), 429),
        'Failed to get AI budget suggestions',
      );
      expect(error, isA<PlanLimitException>());
      expect(error.statusCode, 429);
      expect(error.message, contains('AI chat'));

      final plain = ApiService.apiError(
        http.Response('{"detail":"Email not verified"}', 403),
        'fallback',
      );
      expect(plain, isNot(isA<PlanLimitException>()));
      expect(plain.message, 'Email not verified');
    });

    test('errorMessage shows the plan message instead of a map dump', () {
      final r = http.Response(_planErrorBody(message: 'Used up.'), 429);
      expect(ApiService.errorMessage(r, 'fallback'), 'Used up.');
    });
  });

  group('voice entry', () {
    test('transcription keeps the voice token', () {
      final r = TranscriptionResult.fromJson(
          {'transcription': 'coffee 3000', 'voice_token': 'abc.def'});
      expect(r.transcription, 'coffee 3000');
      expect(r.voiceToken, 'abc.def');
      expect(r.isSilent, isFalse);
    });

    test('a silent recording has no token', () {
      final r = TranscriptionResult.fromJson({'transcription': ''});
      expect(r.isSilent, isTrue);
      expect(r.voiceToken, isNull);
      expect(TranscriptionResult.fromJson({'transcription': '  '}).isSilent, isTrue);
    });

    test('the token goes back with the exact transcript', () {
      expect(ApiService.extractTextBody('coffee 3000', voiceToken: 'abc.def'),
          {'text': 'coffee 3000', 'voice_token': 'abc.def'});
      expect(ApiService.extractTextBody('coffee 3000'), {'text': 'coffee 3000'});
      expect(ApiService.extractTextBody('coffee 3000', voiceToken: ''),
          {'text': 'coffee 3000'});
    });
  });

  group('User plan', () {
    Map<String, dynamic> userJson(String type, {String? expires}) => {
          'id': 'u1',
          'name': 'Maya',
          'email': 'maya@example.com',
          'created_at': '2026-01-01T00:00:00+00:00',
          'subscription_type': type,
          'subscription_expires_at': expires,
        };

    test('plus and pro are paid, free is not', () {
      expect(User.fromJson(userJson('free')).isPaid, isFalse);
      final plus = User.fromJson(userJson('plus'));
      expect([plus.plan, plus.isPaid, plus.isPro], [Plan.plus, true, false]);
      final pro = User.fromJson(userJson('pro'));
      expect([pro.plan, pro.isPaid, pro.isPro], [Plan.pro, true, true]);
    });

    test('an expired paid plan is free at once', () {
      final past = DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String();
      final future = DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String();

      final expired = User.fromJson(userJson('plus', expires: past));
      expect(expired.plan, Plan.plus); // what is stored
      expect(expired.effectivePlan, Plan.free);
      expect(expired.isPaid, isFalse);
      expect(expired.isExpired, isTrue);

      final active = User.fromJson(userJson('pro', expires: future));
      expect(active.isPaid, isTrue);
      expect(active.isExpired, isFalse);
    });

    test('a stray legacy premium value is free', () {
      final user = User.fromJson(userJson('premium'));
      expect(user.plan, Plan.free);
      expect(user.isPaid, isFalse);
    });

    test('subscription-status uses the effective plan', () {
      final s = SubscriptionStatus.fromJson({
        'subscription_type': 'plus',
        'plan': 'free',
        'is_paid': false,
        'is_trial': false,
        'expires_at': '2026-10-01T00:00:00+00:00',
        'is_expired': true,
      });
      expect(s.storedPlan, Plan.plus);
      expect(s.plan, Plan.free);
      expect(s.isPaid, isFalse);
      expect(s.isExpired, isTrue);
    });
  });

  group('strings', () {
    test('plan strings exist in English and Myanmar', () {
      const en = Locale('en');
      const my = Locale('my');
      final getters = <String Function(AppLocalizations)>[
        (l) => l.planNameFree,
        (l) => l.planNameLabel('Plus'),
        (l) => l.planTrialBadge,
        (l) => l.planUsageLeftWeek(1, 2),
        (l) => l.planUsageLeftMonth(1, 2),
        (l) => l.planLimitReachedTitle,
        (l) => l.planFeatureLockedTitle,
        (l) => l.planCostCapTitle,
        (l) => l.planLimitResetsOn('Nov 1'),
        (l) => l.planLimitLockedBody('x'),
        (l) => l.planLimitReachedBody('x'),
        (l) => l.planCostCapBody,
        (l) => l.planSheetNotNow,
        (l) => l.planCurrent,
        (l) => l.planTrialActive('Plus'),
        (l) => l.planTrialEnds('Nov 1'),
        (l) => l.planPerWeek,
        (l) => l.planPerMonth,
        (l) => l.planIncluded,
        (l) => l.planNotIncluded,
        (l) => l.planContactTitle,
        (l) => l.planDetailsUnavailable,
        (l) => l.upgradePlan,
        (l) => l.yourPlanTitle,
        (l) => l.comparePlans,
        (l) => l.planActive('Plus'),
        (l) => l.voiceNothingHeard,
        for (final f in PlanFeature.all) (l) => l.planFeatureName(f),
      ];
      for (final get in getters) {
        final english = get(AppLocalizations(en));
        final myanmar = get(AppLocalizations(my));
        expect(english, isNotEmpty);
        expect(myanmar, isNotEmpty);
        // A missing translation falls back to the camelCase key itself.
        final key = RegExp(r'^[a-z]+[A-Z_]');
        expect(key.hasMatch(english), isFalse, reason: 'EN missing: $english');
        expect(key.hasMatch(myanmar), isFalse, reason: 'MY missing: $myanmar');
        expect(english.contains('{'), isFalse, reason: english);
        expect(myanmar.contains('{'), isFalse, reason: myanmar);
      }
      // The two languages are really translated (not the English text twice).
      expect(AppLocalizations(my).planUsageLeftWeek(3, 5),
          isNot(AppLocalizations(en).planUsageLeftWeek(3, 5)));
      expect(AppLocalizations(my).planCostCapTitle,
          isNot(AppLocalizations(en).planCostCapTitle));
    });
  });

  group('limit sheet', () {
    Future<void> openSheet(WidgetTester tester, PlanLimitException error,
        {Locale locale = const Locale('en')}) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: const [Locale('en'), Locale('my')],
          routes: {
            '/subscription': (_) => const Scaffold(body: Text('upgrade screen')),
          },
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPlanLimitSheet(context, error),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('limit reached: says what ran out and offers Upgrade', (tester) async {
      final error = PlanLimitException.tryParse(429, _planErrorBody())!;
      await openSheet(tester, error);

      expect(find.byKey(const Key('plan-limit-title')), findsOneWidget);
      expect(find.text("You've reached your limit"), findsOneWidget);
      expect(find.text('Ko Toe Pwar chat'), findsOneWidget);
      expect(find.byKey(const Key('plan-limit-body')), findsOneWidget);
      // The sheet writes its own text (the server's message is not shown).
      expect(find.textContaining('Nov 10, 2026'), findsNothing);
      final day = DateTime.utc(2026, 11, 9, 17, 30).toLocal().day; // 9 or 10 by the device's timezone
      expect(find.text("You've used all of your Ko Toe Pwar chat. It resets on $day Nov 2026."),
          findsOneWidget);
      expect(find.byKey(const Key('plan-limit-upgrade')), findsOneWidget);

      await tester.tap(find.byKey(const Key('plan-limit-upgrade')));
      await tester.pumpAndSettle();
      expect(find.text('upgrade screen'), findsOneWidget);
    });

    testWidgets('no Upgrade button when no higher plan exists', (tester) async {
      final error = PlanLimitException.tryParse(
          429, _planErrorBody(upgradeAvailable: false))!;
      await openSheet(tester, error);

      expect(find.byKey(const Key('plan-limit-upgrade')), findsNothing);
      expect(find.byKey(const Key('plan-limit-dismiss')), findsOneWidget);

      await tester.tap(find.byKey(const Key('plan-limit-dismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan-limit-title')), findsNothing);
    });

    testWidgets('locked feature without a server message composes its own text',
        (tester) async {
      final error = PlanLimitException.tryParse(
        403,
        _planErrorBody(
            code: 'plan_feature_locked',
            feature: 'insight_weekly',
            resetsAt: null,
            message: ''),
      )!;
      await openSheet(tester, error);

      expect(find.text('Not included in your plan'), findsOneWidget);
      expect(find.text("Weekly insights isn't part of your plan."), findsOneWidget);
    });

    testWidgets('cost cap shows the monthly AI limit title', (tester) async {
      final error = PlanLimitException.tryParse(
          429, _planErrorBody(code: 'plan_cost_cap', feature: null, message: ''))!;
      await openSheet(tester, error);

      expect(find.text('Monthly AI limit reached'), findsOneWidget);
      expect(find.textContaining("this month's AI limit"), findsOneWidget);
    });

    testWidgets('handlePlanLimitError only handles plan errors', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: const [Locale('en'), Locale('my')],
          home: Builder(builder: (context) {
            captured = context;
            return const Scaffold();
          }),
        ),
      );
      await tester.pumpAndSettle();

      expect(await handlePlanLimitError(captured, ApiException('boom')), isFalse);
      expect(find.byKey(const Key('plan-limit-title')), findsNothing);
    });
  });
}
