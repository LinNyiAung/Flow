import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/custom_insight.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/providers/custom_insight_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/services/notification_event_bus.dart';
import 'package:frontend/utils/custom_insight_ranges.dart';
import 'package:frontend/utils/safe_markdown.dart';

/// The Task 5 detail shape.
Map<String, dynamic> detailJson({
  String id = 'r1',
  String status = 'ready',
  String? content = '## Summary\nAll good.',
  String? contentMm,
  bool figures = true,
}) =>
    {
      'id': id,
      'start_date': '2026-10-01',
      'end_date': '2026-10-31',
      'preset': null,
      'instruction': 'Where did my money go?',
      'status': status,
      'created_at': '2026-11-02T08:15:00.000000+00:00',
      'completed_at': status == 'pending' ? null : '2026-11-02T08:15:20.000000+00:00',
      'has_myanmar': contentMm != null,
      'content': content,
      'content_mm': contentMm,
      'figures': figures
          ? {
              'previous_start': '2026-08-31',
              'previous_end': '2026-09-30',
              'currencies': [
                {
                  'currency': 'MMK',
                  'income': 500000.0,
                  'spending': 250000.5,
                  'net': 249999.5,
                  'transactions': 12,
                  'top_categories': [
                    {'main_category': 'Food', 'sub_category': 'Groceries', 'amount': 90000.0},
                    {'main_category': 'Transport', 'sub_category': '', 'amount': 40000},
                  ],
                  'previous_income': 500000.0,
                  'previous_spending': 100000.0,
                  'income_change_pct': null,
                  'spending_change_pct': 150.0,
                }
              ],
            }
          : null,
    };

Map<String, dynamic> summaryJson(String id, String status) => {
      'id': id,
      'start_date': '2026-10-01',
      'end_date': '2026-10-31',
      'preset': 'where_to_save',
      'instruction': null,
      'status': status,
      'created_at': '2026-11-02T08:15:00+00:00',
      'completed_at': status == 'pending' ? null : '2026-11-02T08:16:00+00:00',
      'has_myanmar': false,
    };

CustomInsight report(String id, String status) =>
    CustomInsight.fromJson(summaryJson(id, status));

class FakeClient implements CustomInsightClient {
  final List<List<CustomInsight>> listAnswers = [];
  Object? listError;
  CustomInsightCreateResult? createResult;
  Object? createError;
  CustomInsight? getResult;
  Object? getError;
  CustomInsight? translateResult;
  Object? translateError;
  Object? deleteError;
  int listCalls = 0;
  final List<String> deleted = [];

  @override
  Future<List<CustomInsight>> list() async {
    listCalls++;
    if (listError != null) throw listError!;
    if (listAnswers.isEmpty) return [];
    return listAnswers.length > 1 ? listAnswers.removeAt(0) : listAnswers.first;
  }

  @override
  Future<CustomInsight> get(String id) async {
    if (getError != null) throw getError!;
    return getResult!;
  }

  @override
  Future<CustomInsightCreateResult> create(CustomInsightRequest request) async {
    if (createError != null) throw createError!;
    return createResult!;
  }

  @override
  Future<CustomInsight> translate(String id) async {
    if (translateError != null) throw translateError!;
    return translateResult!;
  }

  @override
  Future<void> delete(String id) async {
    if (deleteError != null) throw deleteError!;
    deleted.add(id);
  }
}

CustomInsightRequest anyRequest() => CustomInsightRequest(
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 10, 31),
    );

void main() {
  group('model', () {
    test('custom_insight_from_json: detail with figures; unknown status is unknown', () {
      final r = CustomInsight.fromJson(detailJson());
      expect(r.id, 'r1');
      expect(r.status, CustomInsightStatus.ready);
      expect(r.startDate, DateTime(2026, 10, 1));
      expect(r.endDate, DateTime(2026, 10, 31));
      expect(r.preset, isNull);
      expect(r.instruction, 'Where did my money go?');
      expect(r.hasMyanmar, isFalse);
      expect(r.content, startsWith('## Summary'));
      expect(r.completedAt, isNotNull);
      final f = r.figures!;
      expect(f.previousStart, DateTime(2026, 8, 31));
      expect(f.previousEnd, DateTime(2026, 9, 30));
      final c = f.currencies.single;
      expect(c.currency, 'MMK');
      expect(c.spending, 250000.5);
      expect(c.transactions, 12);
      expect(c.topCategories.first.mainCategory, 'Food');
      expect(c.topCategories.first.subCategory, 'Groceries');
      expect(c.topCategories.last.amount, 40000.0); // an int in JSON
      expect(c.spendingChangePct, 150.0);
      expect(c.incomeChangePct, isNull);
      expect(c.previousSpending, 100000.0);
      expect(CustomInsight.fromJson({...detailJson(), 'status': 'weird'}).status,
          CustomInsightStatus.unknown);
    });

    test('custom_insight_from_json: summary row has no content or figures', () {
      final r = report('x', 'pending');
      expect(r.status, CustomInsightStatus.pending);
      expect(r.preset, CustomInsightPreset.whereToSave);
      expect(r.content, isNull);
      expect(r.contentMm, isNull);
      expect(r.figures, isNull);
      expect(r.completedAt, isNull);
      expect(CustomInsightPreset.all, hasLength(4));
      expect(CustomInsightPreset.all, contains('budgets_goals'));
    });

    test('copyWith keeps the rest and sets the translation', () {
      final r = CustomInsight.fromJson(detailJson());
      final t = r.copyWith(contentMm: 'မြန်မာ', hasMyanmar: true);
      expect(t.contentMm, 'မြန်မာ');
      expect(t.hasMyanmar, isTrue);
      expect(t.content, r.content);
      expect(t.id, r.id);
    });

    test('create_result_from_json: 202 new and 200 reused', () {
      final fresh = CustomInsightCreateResult.fromJson({
        'report': detailJson(status: 'pending', content: null),
        'reused': false,
      });
      expect(fresh.reused, isFalse);
      expect(fresh.report.status, CustomInsightStatus.pending);
      final reused = CustomInsightCreateResult.fromJson(
          {'report': detailJson(), 'reused': true});
      expect(reused.reused, isTrue);
      expect(reused.report.status, CustomInsightStatus.ready);
    });

    test('request_to_json: yyyy-MM-dd, trimmed instruction, blank instruction omitted', () {
      final withText = CustomInsightRequest(
        startDate: DateTime(2026, 1, 5),
        endDate: DateTime(2026, 11, 4),
        instruction: '  Why so much on food?  ',
      );
      expect(withText.toJson(), {
        'start_date': '2026-01-05',
        'end_date': '2026-11-04',
        'instruction': 'Why so much on food?',
      });
      final blank = CustomInsightRequest(
        startDate: DateTime(2026, 1, 5),
        endDate: DateTime(2026, 11, 4),
        instruction: '   ',
      );
      expect(blank.toJson().containsKey('instruction'), isFalse);
      final preset = CustomInsightRequest(
        startDate: DateTime(2026, 1, 5),
        endDate: DateTime(2026, 11, 4),
        preset: CustomInsightPreset.comparePrevious,
      );
      expect(preset.toJson(), {
        'start_date': '2026-01-05',
        'end_date': '2026-11-04',
        'preset': 'compare_previous',
      });
    });
  });

  group('ranges', () {
    test('quick_ranges', () {
      final t = DateTime(2026, 11, 4);
      expect(quickRange(CustomQuickRange.last30Days, t).start, DateTime(2026, 10, 6));
      expect(quickRange(CustomQuickRange.last30Days, t).end, t);
      expect(quickRange(CustomQuickRange.last3Months, t).start, DateTime(2026, 8, 5));
      expect(quickRange(CustomQuickRange.thisYear, t).start, DateTime(2026, 1, 1));
      expect(quickRange(CustomQuickRange.thisYear, t).end, t);
      final jan3 = DateTime(2027, 1, 3);
      final y = quickRange(CustomQuickRange.thisYear, jan3);
      expect(customRangeProblem(y.start, y.end, jan3), CustomRangeProblem.tooShort);
    });

    test('quick range 3 months crosses a year and a short month', () {
      expect(quickRange(CustomQuickRange.last3Months, DateTime(2027, 2, 10)).start,
          DateTime(2026, 11, 11));
      // DateTime(2026, 2, 32) rolls over to 4 March: a shorter, still valid range.
      final r = quickRange(CustomQuickRange.last3Months, DateTime(2026, 5, 31));
      expect(r.start, DateTime(2026, 3, 4));
      expect(r.end, DateTime(2026, 5, 31));
    });

    test('range_problem_bounds', () {
      final t = DateTime(2026, 11, 4);
      expect(customRangeProblem(DateTime(2026, 10, 30), t, t), CustomRangeProblem.tooShort); // 6 days
      expect(customRangeProblem(DateTime(2026, 10, 29), t, t), isNull); // 7 days
      expect(customRangeProblem(DateTime(2025, 11, 5), t, t), isNull);
      expect(customRangeProblem(DateTime(2025, 11, 4), t, t), CustomRangeProblem.tooLong);
      expect(customRangeProblem(t, t.add(const Duration(days: 7)), t), CustomRangeProblem.inFuture);
      expect(customRangeProblem(t, DateTime(2026, 10, 1), t), CustomRangeProblem.endBeforeStart);
      expect(customInsightMinDays, 7);
      expect(customInstructionMaxLength, 300);
    });

    test('range_problem_leap_day: one_year_after(Feb 29) is Mar 1, like the server', () {
      final today = DateTime(2025, 6, 1);
      final start = DateTime(2024, 2, 29);
      expect(customRangeProblem(start, DateTime(2025, 2, 28), today), isNull);
      expect(customRangeProblem(start, DateTime(2025, 3, 1), today), CustomRangeProblem.tooLong);
      // An ordinary start: the same date next year is too long, the day before is fine.
      expect(customRangeProblem(DateTime(2024, 3, 1), DateTime(2025, 2, 28), today), isNull);
      expect(customRangeProblem(DateTime(2024, 3, 1), DateTime(2025, 3, 1), today), CustomRangeProblem.tooLong);
    });

    test('range ignores the time of day', () {
      final t = DateTime(2026, 11, 4, 22, 30);
      expect(customRangeProblem(DateTime(2026, 10, 29, 9), DateTime(2026, 11, 4, 1), t), isNull);
    });
  });

  group('safe markdown', () {
    test('safe_markdown: table -> plain text; outline is safe', () {
      expect(hasDisallowedMarkdown('## Summary\n- **Food** up 10%'), isFalse);
      const table = '| a | b |\n|---|---|\n| 1 | 2 |';
      expect(hasDisallowedMarkdown(table), isTrue);
      expect(markdownToPlainText('## Summary\n**Bold** $table'), isNot(contains('|')));
      expect(markdownToPlainText('## Summary\n**Bold**'), 'Summary\nBold');
    });

    test('code fence, html tag and image are disallowed', () {
      expect(hasDisallowedMarkdown('text\n```\ncode\n```'), isTrue);
      expect(hasDisallowedMarkdown('a <b>bold</b> b'), isTrue);
      expect(hasDisallowedMarkdown('see ![chart](http://x/y.png)'), isTrue);
      expect(hasDisallowedMarkdown('a | b in prose, no table'), isFalse);
      expect(hasDisallowedMarkdown('1 < 2 and 3 > 2'), isFalse);
    });

    test('plain text strips emphasis, fences, tags and keeps line breaks', () {
      const md = '## What I found\n- __Rent__ is *high*\n```\ncode\n```\n<br>next';
      final text = markdownToPlainText(md);
      expect(text, isNot(contains('#')));
      expect(text, isNot(contains('__')));
      expect(text, isNot(contains('*')));
      expect(text, isNot(contains('`')));
      expect(text, isNot(contains('<')));
      expect(text, contains('What I found'));
      expect(text, contains('Rent is high'));
      expect(text.split('\n').length, greaterThan(2));
    });

    test('short separator rows still make a table (flutter_markdown takes one dash)', () {
      for (final sep in ['|--|--|', '|-|-|', '| - | - |', '|:-|-:|', '--|--']) {
        final md = '| a | b |\n$sep\n| 1 | 2 |';
        expect(hasDisallowedMarkdown(md), isTrue, reason: sep);
        expect(markdownToPlainText('Intro\n$md'), 'Intro\na · b\n1 · 2', reason: sep);
      }
      // Not tables: a rule, a pipe in prose, a lone separator-looking line, bullets.
      expect(hasDisallowedMarkdown('Title\n---\nText'), isFalse);
      expect(hasDisallowedMarkdown('a | b\n- c'), isFalse);
      expect(hasDisallowedMarkdown('Total\n|-|'), isFalse);
      expect(hasDisallowedMarkdown('- one\n- two'), isFalse);
    });

    test('indented code block is disallowed, a list continuation is not', () {
      expect(hasDisallowedMarkdown('Intro\n\n    final x = 1;\n'), isTrue);
      expect(hasDisallowedMarkdown('Intro\n\n\tcode'), isTrue);
      // Nested bullets and an indented paragraph of a list item are not code.
      expect(hasDisallowedMarkdown('- one\n    - nested\n- two'), isFalse);
      expect(hasDisallowedMarkdown('- one\n\n    more about one\n- two'), isFalse);
      expect(hasDisallowedMarkdown('1. one\n\n    more about one'), isFalse);
      // Indent without a blank line before it is a lazy continuation.
      expect(hasDisallowedMarkdown('Intro\n    wrapped line'), isFalse);
      // The outline the AI is asked for.
      expect(
        hasDisallowedMarkdown(
            '## Summary\nText.\n\n## What I found\n- **Food** up 10%\n  - detail\n\n## What to do next\n- Save'),
        isFalse,
      );
    });

    test('table rows become plain cells', () {
      final text = markdownToPlainText('| Cat | Amount |\n|:---|---:|\n| Food | 10 |');
      expect(text, isNot(contains('---')));
      expect(text, contains('Cat'));
      expect(text, contains('Food'));
      expect(text, contains('10'));
      expect(text, 'Cat · Amount\nFood · 10');
    });
  });

  group('timeouts', () {
    test('custom insight calls, translate included, get the 90 s timeout', () {
      Duration t(String path) => ApiService.timeoutFor(Uri.parse('https://x.test$path'));
      expect(t('/api/custom-insights'), const Duration(seconds: 90));
      expect(t('/api/custom-insights/x/translate'), const Duration(seconds: 90));
      expect(t('/api/custom-insights/x'), const Duration(seconds: 90));
    });
  });

  group('request exception', () {
    test('request_exception_parse: 409 pending, 429 attempts with resets_at; plan codes are not custom', () {
      final pending = CustomInsightRequestException.tryParse(
        409,
        jsonEncode({
          'detail': {
            'code': 'custom_insight_pending',
            'message': 'Wait.',
            'resets_at': null,
          }
        }),
      )!;
      expect(pending.code, CustomInsightRequestException.pending);
      expect(pending.statusCode, 409);
      expect(pending.message, 'Wait.');
      expect(pending.resetsAt, isNull);

      final attempts = CustomInsightRequestException.tryParse(
        429,
        jsonEncode({
          'detail': {
            'code': 'custom_insight_attempts',
            'message': 'Too many.',
            'resets_at': '2026-11-05T17:30:00+00:00',
          }
        }),
      )!;
      expect(attempts.code, CustomInsightRequestException.attempts);
      expect(attempts.resetsAt, DateTime.utc(2026, 11, 5, 17, 30).toLocal());

      final future = CustomInsightRequestException.tryParse(
          422, jsonEncode({'detail': {'code': 'custom_insight_future_code', 'message': 'x'}}));
      expect(future, isNotNull);
      expect(future!.code, 'custom_insight_future_code');

      expect(
        CustomInsightRequestException.tryParse(
            429, jsonEncode({'detail': {'code': 'plan_limit_reached', 'message': 'x'}})),
        isNull,
      );
      expect(CustomInsightRequestException.tryParse(500, 'not json'), isNull);
      expect(CustomInsightRequestException.tryParse(404, jsonEncode({'detail': 'Custom insight not found'})), isNull);
      expect(CustomInsightRequestException.tryParse(422, jsonEncode({'detail': [{'msg': 'x'}]})), isNull);
    });
  });

  group('provider', () {
    test('provider_create_polls_until_ready_and_refreshes_usage_on_refused', () async {
      final client = FakeClient()
        ..createResult = CustomInsightCreateResult(report: report('r1', 'pending'), reused: false)
        ..listAnswers.addAll([
          [report('r1', 'pending')],
          [report('r1', 'refused')],
        ]);
      var usageChanged = 0;
      final p = CustomInsightProvider(
        client: client,
        pollInterval: const Duration(milliseconds: 10),
        onUsageChanged: () => usageChanged++,
      );
      final result = await p.create(anyRequest());
      expect(result, isNotNull);
      expect(p.reports.first.id, 'r1');
      expect(p.hasPending, isTrue);

      for (var i = 0; i < 100 && p.hasPending; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(p.hasPending, isFalse);
      expect(p.reports.first.status, CustomInsightStatus.refused);
      expect(usageChanged, 1);

      // The poll stopped: no more list calls.
      final calls = client.listCalls;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(client.listCalls, calls);
      p.dispose();
    });

    test('a report that turns ready does not refresh usage and drops its cached detail', () async {
      final client = FakeClient()
        ..createResult = CustomInsightCreateResult(
            report: CustomInsight.fromJson(detailJson(id: 'r1', status: 'pending', content: null)),
            reused: false)
        ..listAnswers.add([report('r1', 'ready')]);
      var usageChanged = 0;
      final p = CustomInsightProvider(
        client: client,
        pollInterval: const Duration(milliseconds: 10),
        onUsageChanged: () => usageChanged++,
      );
      await p.create(anyRequest());
      expect(p.detail('r1'), isNotNull);
      for (var i = 0; i < 100 && p.hasPending; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(p.reports.first.status, CustomInsightStatus.ready);
      expect(usageChanged, 0);
      expect(p.detail('r1'), isNull); // refetch on open
      p.dispose();
    });

    test('provider_create_error_codes', () async {
      final client = FakeClient();
      final p = CustomInsightProvider(client: client, onUsageChanged: () {});

      client.createError = CustomInsightRequestException(
        code: CustomInsightRequestException.pending,
        statusCode: 409,
        message: 'Wait.',
      );
      expect(await p.create(anyRequest()), isNull);
      expect(p.lastErrorCode, CustomInsightRequestException.pending);
      expect(p.lastError, 'Wait.');
      expect(p.lastPlanLimit, isNull);
      expect(p.reports, isEmpty);

      client.createError = PlanLimitException(
        code: PlanLimitException.codeLocked,
        statusCode: 403,
        message: 'Pro only.',
        feature: PlanFeature.insightCustom,
      );
      expect(await p.create(anyRequest()), isNull);
      expect(p.lastPlanLimit, isNotNull);
      expect(p.lastPlanLimit!.feature, 'insight_custom');
      expect(p.lastErrorCode, PlanLimitException.codeLocked);

      client.createError = ApiException('Boom', statusCode: 500);
      expect(await p.create(anyRequest()), isNull);
      expect(p.lastPlanLimit, isNull);
      expect(p.lastErrorCode, isNull);
      expect(p.lastError, 'Boom');

      // A good call clears the failure.
      client.createError = null;
      client.createResult = CustomInsightCreateResult(report: report('r9', 'ready'), reused: true);
      final ok = await p.create(anyRequest());
      expect(ok!.reused, isTrue);
      expect(p.lastError, isNull);
      expect(p.lastErrorCode, isNull);
      expect(p.hasPending, isFalse); // ready: no polling
      p.dispose();
    });

    test('load fills the list; failure sets error; pending local report survives a stale list', () async {
      final client = FakeClient()
        ..listAnswers.add([report('a', 'ready'), report('b', 'failed')]);
      final p = CustomInsightProvider(client: client, pollInterval: const Duration(hours: 1), onUsageChanged: () {});
      await p.load();
      expect(p.reports.map((r) => r.id), ['a', 'b']);
      expect(p.isLoading, isFalse);
      expect(p.error, isNull);

      client.createResult = CustomInsightCreateResult(report: report('n', 'pending'), reused: false);
      await p.create(anyRequest());
      expect(p.reports.first.id, 'n');
      // The list answer predates the new report: it must not vanish.
      await p.load();
      expect(p.reports.map((r) => r.id), contains('n'));
      expect(p.hasPending, isTrue);

      client.listError = ApiException('Down', statusCode: 500);
      await p.load();
      expect(p.error, 'Down');
      expect(p.reports, isNotEmpty); // keeps what it had
      p.dispose();
    });

    test('open caches the detail; 404 sets notFound; other errors do not', () async {
      final client = FakeClient()..getResult = CustomInsight.fromJson(detailJson());
      final p = CustomInsightProvider(client: client, onUsageChanged: () {});
      final r = await p.open('r1');
      expect(r!.content, isNotNull);
      expect(p.notFound, isFalse);
      expect(p.detail('r1'), same(r));

      client.getError = ApiException('Custom insight not found', statusCode: 404);
      expect(await p.open('gone'), isNull);
      expect(p.notFound, isTrue);

      client.getError = ApiException('Down', statusCode: 500);
      expect(await p.open('r1'), isNull);
      expect(p.notFound, isFalse);
      expect(p.lastError, 'Down');

      client.getError = null;
      expect(await p.open('r1'), isNotNull);
      expect(p.notFound, isFalse);
      p.dispose();
    });

    test('translate stores the Myanmar text; failure keeps the report and fills lastPlanLimit', () async {
      final client = FakeClient()
        ..getResult = CustomInsight.fromJson(detailJson())
        ..translateResult = CustomInsight.fromJson(detailJson(contentMm: 'မြန်မာ'));
      final p = CustomInsightProvider(client: client, onUsageChanged: () {});
      await p.open('r1');
      final t = await p.translate('r1');
      expect(t!.contentMm, 'မြန်မာ');
      expect(p.detail('r1')!.contentMm, 'မြန်မာ');

      client.translateError = PlanLimitException(
          code: PlanLimitException.codeLocked, statusCode: 403, feature: 'insight_translation');
      expect(await p.translate('r1'), isNull);
      expect(p.lastPlanLimit!.feature, 'insight_translation');
      expect(p.detail('r1')!.contentMm, 'မြန်မာ');
      p.dispose();
    });

    test('provider_delete_and_reset', () async {
      final client = FakeClient()
        ..listAnswers.add([report('a', 'ready'), report('b', 'ready')])
        ..getResult = CustomInsight.fromJson(detailJson(id: 'a'));
      final p = CustomInsightProvider(client: client, onUsageChanged: () {});
      await p.load();
      await p.open('a');
      expect(await p.delete('a'), isTrue);
      expect(client.deleted, ['a']);
      expect(p.reports.map((r) => r.id), ['b']);
      expect(p.detail('a'), isNull);

      client.deleteError = CustomInsightRequestException(
          code: CustomInsightRequestException.notReady, statusCode: 409, message: 'Not yet.');
      expect(await p.delete('b'), isFalse);
      expect(p.lastErrorCode, CustomInsightRequestException.notReady);
      expect(p.reports.map((r) => r.id), ['b']);

      // Gone already (404) counts as deleted.
      client.deleteError = ApiException('Custom insight not found', statusCode: 404);
      expect(await p.delete('b'), isTrue);
      expect(p.reports, isEmpty);

      client.createResult = CustomInsightCreateResult(report: report('c', 'pending'), reused: false);
      await p.create(anyRequest());
      expect(p.hasPending, isTrue);
      p.reset();
      expect(p.reports, isEmpty);
      expect(p.hasPending, isFalse);
      expect(p.lastError, isNull);
      expect(p.notFound, isFalse);
      final calls = client.listCalls;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(client.listCalls, calls); // the timer is gone
      p.dispose();
    });

    test('the event bus makes a loaded provider reload', () async {
      final client = FakeClient()..listAnswers.add([report('a', 'ready')]);
      final p = CustomInsightProvider(client: client, pollInterval: const Duration(hours: 1), onUsageChanged: () {});
      await p.load();
      client.listAnswers
        ..clear()
        ..add([report('a', 'ready'), report('b', 'ready')]);
      NotificationEventBus().notifyCustomInsightUpdated();
      for (var i = 0; i < 50 && p.reports.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(p.reports.map((r) => r.id), ['a', 'b']);
      p.dispose();
    });

    test('a reset provider ignores the event bus', () async {
      final client = FakeClient()..listAnswers.add([report('a', 'ready')]);
      final p = CustomInsightProvider(client: client, onUsageChanged: () {});
      await p.load();
      p.reset();
      final calls = client.listCalls;
      NotificationEventBus().notifyCustomInsightUpdated();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(client.listCalls, calls);
      p.dispose();
    });
  });

  test('plan_feature_custom_named_in_both_languages', () {
    expect(PlanFeature.insightCustom, 'insight_custom');
    expect(PlanFeature.all, contains(PlanFeature.insightCustom));
    expect(PlanFeature.all.indexOf(PlanFeature.insightCustom),
        PlanFeature.all.indexOf(PlanFeature.insightTranslation) + 1);
    final en = AppLocalizations(const Locale('en'));
    final my = AppLocalizations(const Locale('my'));
    expect(en.knownPlanFeatureName('insight_custom'), 'Custom insights');
    expect(my.knownPlanFeatureName('insight_custom'), isNotNull);
    expect(my.knownPlanFeatureName('insight_custom'), isNot('Custom insights'));
  });
}
