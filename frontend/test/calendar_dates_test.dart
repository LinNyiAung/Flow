// Calendar dates and local date-times (schema project #4): the app sends the
// phone's timezone and honest date shapes, and reads them back as local days.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/custom_insight.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/recurring_transaction.dart';
import 'package:frontend/models/report.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/budgets/create_budget_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/utils/date_parsing.dart';
import 'package:frontend/utils/spending_pace.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _transactionJson({String date = '2026-11-18T23:40:00'}) => {
      'id': 't1',
      'book_id': 'b1',
      'type': 'outflow',
      'main_category': 'Food',
      'sub_category': 'Lunch',
      'date': date,
      'description': null,
      'amount': 12.5,
      'currency': 'usd',
      'created_at': '2026-11-18T17:10:00+00:00',
      'updated_at': '2026-11-18T17:10:00+00:00',
    };

Map<String, dynamic> _budgetJson({String start = '2026-11-01', String end = '2026-11-30'}) => {
      'id': 'bu1',
      'book_id': 'b1',
      'name': 'November',
      'period': 'monthly',
      'start_date': start,
      'end_date': end,
      'category_budgets': <dynamic>[],
      'total_budget': 100,
      'total_spent': 10,
      'remaining_budget': 90,
      'percentage_used': 10,
      'status': 'active',
      'description': null,
      'is_active': true,
      'created_at': '2026-11-01T02:00:00+00:00',
      'updated_at': '2026-11-01T02:00:00+00:00',
      'currency': 'usd',
    };

Map<String, dynamic> _goalJson({String? targetDate = '2026-12-24'}) => {
      'id': 'g1',
      'book_id': 'b1',
      'name': 'Trip',
      'target_amount': 500,
      'current_amount': 0,
      'target_date': targetDate,
      'goal_type': 'savings',
      'status': 'active',
      'progress_percentage': 0,
      'created_at': '2026-11-01T02:00:00+00:00',
      'updated_at': '2026-11-01T02:00:00+00:00',
      'achieved_at': null,
      'currency': 'usd',
    };

Map<String, dynamic> _reportJson() => {
      'period': 'custom',
      'start_date': '2026-11-01T00:00:00',
      'end_date': '2026-11-30T23:59:59.999999',
      'total_inflow': 0,
      'total_outflow': 0,
      'net_balance': 0,
      'inflow_by_category': <dynamic>[],
      'outflow_by_category': <dynamic>[],
      'goals': <dynamic>[],
      'total_allocated_to_goals': 0,
      'total_transactions': 0,
      'inflow_count': 0,
      'outflow_count': 0,
      'average_daily_inflow': 0,
      'average_daily_outflow': 0,
      'generated_at': '2026-11-30T10:00:00+00:00',
      'currency': 'usd',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> requests;
  late Object? Function(http.Request request) respond;

  setUp(() {
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
    requests = [];
    respond = (_) => <String, dynamic>{};
    ApiService.httpClientOverride = MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(respond(request)), 200,
          headers: {'content-type': 'application/json'});
    });
    ApiService.timezoneOverride = () async => 'Asia/Tokyo';
  });

  tearDown(() {
    ApiService.httpClientOverride = null;
    ApiService.timezoneOverride = null;
  });

  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  group('X-Timezone header', () {
    test('every request carries the phone\'s zone, read once', () async {
      var reads = 0;
      ApiService.timezoneOverride = () async {
        reads++;
        return 'Asia/Tokyo';
      };
      respond = (_) => <dynamic>[];
      await ApiService.getGoals();
      await ApiService.getTransactions();
      respond = (_) => _transactionJson();
      await ApiService.createTransaction(
        type: TransactionType.outflow,
        mainCategory: 'Food',
        subCategory: 'Lunch',
        date: DateTime(2026, 11, 18, 23, 40),
        amount: 12.5,
        currency: Currency.usd,
      );

      expect(requests, hasLength(3));
      for (final r in requests) {
        expect(r.headers['X-Timezone'], 'Asia/Tokyo', reason: r.url.path);
      }
      expect(reads, 1);
    });

    test('a failed read sends no header and the request still goes out', () async {
      ApiService.timezoneOverride = () async => throw Exception('no zone');
      respond = (_) => <dynamic>[];

      final goals = await ApiService.getGoals();

      expect(goals, isEmpty);
      expect(requests, hasLength(1));
      expect(requests.single.headers.containsKey('X-Timezone'), isFalse);
      expect(requests.single.headers['Authorization'], 'Bearer tok');
    });

    test('a failed read is tried again: the next request carries the zone', () async {
      var reads = 0;
      ApiService.timezoneOverride = () async {
        reads++;
        if (reads == 1) throw Exception('not yet');
        return 'Asia/Bangkok';
      };
      respond = (_) => <dynamic>[];

      await ApiService.getGoals();
      await ApiService.getGoals();

      expect(requests, hasLength(2));
      expect(requests[0].headers.containsKey('X-Timezone'), isFalse);
      expect(requests[1].headers['X-Timezone'], 'Asia/Bangkok');
      expect(reads, 2);
    });

    testWidgets('a read that never answers: the request goes out without the zone after 2 seconds',
        (tester) async {
      ApiService.timezoneOverride = () => Completer<String>().future;
      respond = (_) => <dynamic>[];

      var finished = false;
      final call = ApiService.getGoals().then((_) => finished = true);
      await tester.pump(const Duration(milliseconds: 1900));
      expect(requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));

      expect(requests, hasLength(1));
      expect(requests.single.headers.containsKey('X-Timezone'), isFalse);
      expect(requests.single.headers['Authorization'], 'Bearer tok');
      await call;
      expect(finished, isTrue);
    });

    test('a zone with a space or over 64 characters is not sent', () async {
      respond = (_) => <dynamic>[];
      for (final bad in ['Asia/Ho Chi Minh', 'Asia/${'x' * 60}']) {
        ApiService.timezoneOverride = () async => bad;
        await ApiService.getGoals();
      }
      final longest = 'Asia/${'x' * 59}';
      ApiService.timezoneOverride = () async => longest;
      await ApiService.getGoals();

      expect(requests, hasLength(3));
      expect(requests[0].headers.containsKey('X-Timezone'), isFalse);
      expect(requests[1].headers.containsKey('X-Timezone'), isFalse);
      expect(requests[2].headers['X-Timezone'], longest);
    });
  });

  group('transaction-style dates are local date-times with no offset', () {
    test('creating a transaction for 18 Nov 23:40 sends that wall clock', () async {
      respond = (_) => _transactionJson();

      final created = await ApiService.createTransaction(
        type: TransactionType.outflow,
        mainCategory: 'Food',
        subCategory: 'Lunch',
        date: DateTime(2026, 11, 18, 23, 40),
        amount: 12.5,
        currency: Currency.usd,
      );

      expect(body(requests.single)['date'], '2026-11-18T23:40:00.000');
      expect(created.date, DateTime(2026, 11, 18, 23, 40));
      expect(created.date.isUtc, isFalse);
    });

    test('updating a transaction and moving money send no Z', () async {
      respond = (_) => _transactionJson();
      await ApiService.updateTransaction(transactionId: 't1', date: DateTime(2026, 11, 18, 23, 40));
      expect(body(requests.last)['date'], '2026-11-18T23:40:00.000');

      respond = (_) => {'transfer_id': 'tr1'};
      await ApiService.createTransfer(
        direction: TransferDirection.toFamily,
        amount: 5,
        currency: Currency.usd,
        date: DateTime(2026, 11, 18, 23, 40),
      );
      expect(body(requests.last)['date'], '2026-11-18T23:40:00.000');
    });

    test('the transaction filter sends a local start and the end as a day (the server includes all of it)',
        () async {
      respond = (_) => <dynamic>[];
      await ApiService.getTransactions(
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 30),
      );
      // A time on the end day is ignored: 23:59:59 would have missed entries in its last second.
      await ApiService.getTransactions(endDate: DateTime(2026, 11, 30, 23, 59, 59));
      final q = requests.first.url.queryParameters;
      expect(q['start_date'], '2026-11-01T00:00:00.000');
      expect(q['end_date'], '2026-11-30');
      expect(requests.last.url.queryParameters['end_date'], '2026-11-30');
    });

    test('recurrence preview: local start, calendar end date', () async {
      respond = (_) => {
            'occurrences': ['2026-12-18T23:40:00']
          };
      final occurrences = await ApiService.previewRecurrence(
        recurrence: TransactionRecurrence(
          enabled: true,
          config: RecurrenceConfig(
            frequency: RecurrenceFrequency.monthly,
            dayOfMonth: 18,
            endDate: DateTime(2027, 6, 30),
          ),
        ),
        startDate: DateTime(2026, 11, 18, 23, 40),
      );
      final sent = body(requests.single);
      expect(sent['start_date'], '2026-11-18T23:40:00.000');
      expect(sent['end_date'], '2027-06-30');
      expect(occurrences.single, DateTime(2026, 12, 18, 23, 40));
    });

    test('a recurrence end date goes out and comes back as a calendar date', () {
      final config = RecurrenceConfig.fromJson({'frequency': 'monthly', 'day_of_month': 5, 'end_date': '2027-06-30'});
      expect(config.endDate, DateTime(2027, 6, 30));
      expect(config.toJson()['end_date'], '2027-06-30');
    });
  });

  group('budgets use calendar dates', () {
    test('creating a budget 1 Nov to 30 Nov sends the two days', () async {
      respond = (_) => _budgetJson();

      await ApiService.createBudget(
        name: 'November',
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 30),
        categoryBudgets: const [],
        totalBudget: 100,
        currency: Currency.usd,
      );

      final sent = body(requests.single);
      expect(sent['start_date'], '2026-11-01');
      expect(sent['end_date'], '2026-11-30');
    });

    test('budget ideas send calendar dates too', () async {
      respond = (_) => {
            'suggested_name': 'November',
            'period': 'monthly',
            'start_date': '2026-11-01',
            'end_date': '2026-11-30',
            'category_budgets': <dynamic>[],
            'total_budget': 100,
            'reasoning': '',
            'data_confidence': 1,
            'warnings': <dynamic>[],
            'analysis_summary': <String, dynamic>{},
            'currency': 'usd',
          };
      final idea = await ApiService.getAIBudgetSuggestions(
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 30),
        currency: Currency.usd,
      );
      final sent = body(requests.single);
      expect(sent['start_date'], '2026-11-01');
      expect(sent['end_date'], '2026-11-30');
      expect(idea.endDate, DateTime(2026, 11, 30));
    });

    test('a budget ending "2026-11-30" runs all of 30 Nov', () {
      final budget = Budget.fromJson(_budgetJson());

      expect(budget.startDate, DateTime(2026, 11, 1));
      expect(budget.endDate, DateTime(2026, 11, 30));
      expect(budget.endDate.isUtc, isFalse);
      expect(budget.hasEndedAt(DateTime(2026, 11, 30, 23, 59, 59)), isFalse);
      expect(budget.countsTowardHealthScore(DateTime(2026, 11, 30, 23, 59)), isTrue);
      expect(budget.hasEndedAt(DateTime(2026, 12, 1)), isTrue);
      expect(budget.countsTowardHealthScore(DateTime(2026, 12, 1, 0, 1)), isFalse);
    });

    test('days left: 0 on the last day, 1 the day before', () {
      final budget = Budget.fromJson(_budgetJson());

      expect(budget.daysLeftOn(DateTime(2026, 11, 30, 0, 5)), 0);
      expect(budget.daysLeftOn(DateTime(2026, 11, 30, 23, 59)), 0);
      expect(budget.daysLeftOn(DateTime(2026, 11, 29, 0, 1)), 1);
      expect(budget.daysLeftOn(DateTime(2026, 11, 29, 23, 59)), 1);
      expect(budget.daysLeftOn(DateTime(2026, 11, 1, 9)), 29);
      expect(budget.daysLeftOn(DateTime(2026, 12, 1, 9)), -1);
    });

    test('the create screen picks included end dates', () {
      expect(periodEndFor(BudgetPeriod.weekly, DateTime(2026, 11, 16)), DateTime(2026, 11, 22));
      expect(periodEndFor(BudgetPeriod.monthly, DateTime(2026, 11, 1)), DateTime(2026, 11, 30));
      expect(periodEndFor(BudgetPeriod.monthly, DateTime(2026, 2, 1)), DateTime(2026, 2, 28));
      expect(periodEndFor(BudgetPeriod.yearly, DateTime(2026, 1, 1)), DateTime(2026, 12, 31));
      expect(periodEndFor(BudgetPeriod.custom, DateTime(2026, 11, 1)), isNull);
      // 30 days in all, the end date included.
      expect(defaultCustomEnd(DateTime(2026, 11, 1)), DateTime(2026, 11, 30));
      // A weekly budget across a DST change still ends on the Sunday.
      expect(periodEndFor(BudgetPeriod.weekly, DateTime(2026, 3, 23)), DateTime(2026, 3, 29));
    });
  });

  group('goals use calendar dates', () {
    test('target date goes out and comes back as a day', () async {
      respond = (_) => _goalJson();
      final goal = await ApiService.createGoal(
        name: 'Trip',
        targetAmount: 500,
        targetDate: DateTime(2026, 12, 24),
        goalType: GoalType.savings,
        currency: Currency.usd,
      );
      expect(body(requests.single)['target_date'], '2026-12-24');
      expect(goal.targetDate, DateTime(2026, 12, 24));

      await ApiService.updateGoal(goalId: 'g1', targetDate: DateTime(2027, 1, 5));
      expect(body(requests.last)['target_date'], '2027-01-05');
    });

    test('a goal due today is not overdue; due yesterday is', () {
      final goal = Goal.fromJson(_goalJson(targetDate: '2026-11-18'));
      expect(goal.isOverdueOn(DateTime(2026, 11, 18, 23, 59)), isFalse);
      expect(goal.isOverdueOn(DateTime(2026, 11, 19, 0, 1)), isTrue);
    });
  });

  group('reports', () {
    test('a report request has no timezone_offset; custom days are dates', () async {
      respond = (_) => _reportJson();

      final report = await ApiService.generateReport(
        period: ReportPeriod.custom,
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 30),
      );

      final sent = body(requests.single);
      expect(sent.containsKey('timezone_offset'), isFalse);
      expect(sent['start_date'], '2026-11-01');
      expect(sent['end_date'], '2026-11-30');
      // The period ends at 23:59:59.999999 local: shown as the 30th.
      expect(report.endDate.year, 2026);
      expect(report.endDate.month, 11);
      expect(report.endDate.day, 30);
      expect(report.daysCovered, 30);
    });

    test('download and all-currency reports send no timezone_offset either', () async {
      respond = (_) => <String, dynamic>{};
      await ApiService.downloadReportPdf(period: ReportPeriod.month);
      respond = (_) => {
            'period': 'month',
            'start_date': '2026-11-01T00:00:00',
            'end_date': '2026-11-30T23:59:59.999999',
            'currency_reports': <dynamic>[],
            'generated_at': '2026-11-30T10:00:00+00:00',
          };
      try {
        await ApiService.generateMultiCurrencyReport(period: ReportPeriod.month);
      } catch (_) {
        // Only the request matters here.
      }
      expect(requests, hasLength(2));
      for (final r in requests) {
        expect(body(r).containsKey('timezone_offset'), isFalse, reason: r.url.path);
      }
    });
  });

  group('spending pace', () {
    test('fetches the last 7 local days without Z, and 23:40 counts on the 18th', () async {
      respond = (_) => [_transactionJson(date: '2026-11-18T23:40:00')];
      final provider = TransactionProvider();

      await provider.fetchWeekSpending(today: DateTime(2026, 11, 18, 9));

      final q = requests.single.url.queryParameters;
      expect(q['start_date'], '2026-11-12T00:00:00.000');
      expect(q['end_date'], '2026-11-18');
      final pace = buildSpendingPace(provider.weekOutflows, today: DateTime(2026, 11, 18, 9));
      expect(pace.days.last, DateTime(2026, 11, 18));
      expect(pace.totalsFor(Currency.usd), [0, 0, 0, 0, 0, 0, 12.5]);
    });
  });

  group('other calendar-date requests', () {
    test('family breakdown and custom insights send plain days', () async {
      respond = (_) => <String, dynamic>{};
      try {
        await ApiService.getFamilyBreakdown(DateTime(2026, 11, 1), DateTime(2026, 11, 30));
      } catch (_) {
        // Only the request matters here.
      }
      final q = requests.single.url.queryParameters;
      expect(q['start_date'], '2026-11-01');
      expect(q['end_date'], '2026-11-30');

      final request = CustomInsightRequest(startDate: DateTime(2026, 10, 1), endDate: DateTime(2026, 10, 31));
      expect(request.toJson()['start_date'], '2026-10-01');
      expect(request.toJson()['end_date'], '2026-10-31');
    });
  });

  group('date helpers', () {
    test('parseCalendarDate reads a day as local midnight', () {
      final d = parseCalendarDate('2026-11-30');
      expect(d, DateTime(2026, 11, 30));
      expect(d.isUtc, isFalse);
      // A date-time keeps its date part, whatever its time or offset.
      expect(parseCalendarDate('2026-11-30T23:59:59.999999'), DateTime(2026, 11, 30));
      expect(parseCalendarDate('2026-11-30T00:00:00Z'), DateTime(2026, 11, 30));
      expect(parseCalendarDateOrNull(null), isNull);
      expect(parseCalendarDateOrNull('not a date'), isNull);
      expect(parseCalendarDateOrNull('2026-01-05'), DateTime(2026, 1, 5));
    });

    test('toCalendarDateString and toWallClockString write local fields', () {
      expect(toCalendarDateString(DateTime(2026, 1, 5, 23, 40)), '2026-01-05');
      expect(toCalendarDateString(DateTime(987, 3, 9)), '0987-03-09');
      expect(toWallClockString(DateTime(2026, 11, 18, 23, 40)), '2026-11-18T23:40:00.000');
      expect(toWallClockString(DateTime(2026, 11, 18, 23, 40)).endsWith('Z'), isFalse);
      // An instant is written as the phone's wall clock for it.
      final instant = DateTime.utc(2026, 11, 18, 16, 40);
      expect(toWallClockString(instant), toWallClockString(instant.toLocal()));
      expect(toWallClockString(instant).endsWith('Z'), isFalse);
    });

    test('parseWallClock reads offset-less strings as local', () {
      final d = parseWallClock('2026-11-18T23:40:00');
      expect(d, DateTime(2026, 11, 18, 23, 40));
      expect(d.isUtc, isFalse);
    });
  });
}
