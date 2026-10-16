import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/goals/goal_detail_screen.dart';
import 'package:frontend/screens/transactions/add_transaction_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/services/pending_fcm_unregister.dart';
import 'package:frontend/utils/date_picker_bounds.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _goalJson({required String targetDate, String status = 'active'}) => {
      'id': 'g1',
      'user_id': 'u1',
      'name': 'New phone',
      'target_amount': 1000,
      'current_amount': 250,
      'target_date': targetDate,
      'goal_type': 'savings',
      'status': status,
      'progress_percentage': 25,
      'created_at': '2026-01-01T00:00:00+00:00',
      'updated_at': '2026-01-01T00:00:00+00:00',
      'currency': 'usd',
    };

Map<String, dynamic> _budgetJson({
  required String status,
  required String start,
  required String end,
  bool isActive = true,
}) =>
    {
      'id': 'b1',
      'user_id': 'u1',
      'name': 'October',
      'period': 'monthly',
      'start_date': start,
      'end_date': end,
      'category_budgets': [],
      'total_budget': 100,
      'total_spent': 150,
      'remaining_budget': -50,
      'percentage_used': 150,
      'status': status,
      'is_active': isActive,
      'created_at': '2026-10-01T00:00:00+00:00',
      'updated_at': '2026-10-01T00:00:00+00:00',
      'currency': 'usd',
    };

Widget _addTransactionApp() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
      ],
      child: MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en'), Locale('my')],
        home: AddTransactionScreen(),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('date picker bounds', () {
    test('initial date before firstDate (overdue goal) is clamped up', () {
      final b = DatePickerBounds.clamped(
        initialDate: DateTime(2026, 10, 7),
        firstDate: DateTime(2026, 10, 10, 15, 30),
        lastDate: DateTime(2036, 10, 10),
      );
      expect(b.firstDate, DateTime(2026, 10, 10));
      expect(b.initialDate, DateTime(2026, 10, 10));
      expect(b.lastDate, DateTime(2036, 10, 10));
    });

    test('initial date after lastDate (budget end) is clamped down', () {
      final b = DatePickerBounds.clamped(
        initialDate: DateTime(2027, 11, 9),
        firstDate: DateTime(2027, 10, 10),
        lastDate: DateTime(2027, 10, 10, 9),
      );
      expect(b.initialDate, DateTime(2027, 10, 10));
      expect(b.lastDate, DateTime(2027, 10, 10));
    });

    test('lastDate before firstDate is widened; null initial uses firstDate', () {
      final b = DatePickerBounds.clamped(
        initialDate: null,
        firstDate: DateTime(2027, 1, 2),
        lastDate: DateTime(2026, 1, 1),
      );
      expect(b.lastDate, b.firstDate);
      expect(b.initialDate, DateTime(2027, 1, 2));
    });

    test('UTC wall-clock dates keep their calendar day', () {
      final b = DatePickerBounds.clamped(
        initialDate: DateTime.utc(2026, 10, 31, 23, 59, 59),
        firstDate: DateTime.utc(2026, 10, 1),
        lastDate: DateTime(2027, 10, 1),
      );
      expect(b.initialDate, DateTime(2026, 10, 31));
      expect(b.firstDate, DateTime(2026, 10, 1));
    });

    test('laterDate', () {
      expect(laterDate(DateTime(2026), DateTime(2027)), DateTime(2027));
      expect(laterDate(DateTime(2028), DateTime(2027)), DateTime(2028));
    });
  });

  group('overdue goals', () {
    final now = DateTime(2026, 10, 10, 9);

    test('active goal due before today is overdue; due today is not', () {
      expect(Goal.fromJson(_goalJson(targetDate: '2026-10-07T00:00:00+00:00')).isOverdueOn(now), isTrue);
      expect(Goal.fromJson(_goalJson(targetDate: '2026-10-10T00:00:00+00:00')).isOverdueOn(now), isFalse);
      expect(Goal.fromJson(_goalJson(targetDate: '2026-11-01T00:00:00+00:00')).isOverdueOn(now), isFalse);
    });

    test('achieved goals and goals without a date are never overdue', () {
      expect(
        Goal.fromJson(_goalJson(targetDate: '2026-10-07T00:00:00+00:00', status: 'achieved')).isOverdueOn(now),
        isFalse,
      );
      final noDate = _goalJson(targetDate: '')..['target_date'] = null;
      expect(Goal.fromJson(noDate).isOverdueOn(now), isFalse);
    });

    test('due date label adds the year only when it differs', () {
      expect(formatOverdueDueDate(DateTime(2026, 10, 7), now: now), 'Oct 07');
      expect(formatOverdueDueDate(DateTime(2025, 12, 20), now: now), 'Dec 20, 2025');
    });

    testWidgets('detail shows the overdue state and the edit date picker opens', (tester) async {
      final goal = Goal.fromJson(_goalJson(targetDate: '2025-10-07T00:00:00+00:00'));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => GoalProvider()),
            ChangeNotifierProvider(create: (_) => TransactionProvider()),
          ],
          child: MaterialApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: const [Locale('en'), Locale('my')],
            home: GoalDetailScreen(goal: goal),
          ),
        ),
      );
      await tester.pump();

      final l = AppLocalizations(const Locale('en'));
      expect(find.byKey(const ValueKey('goal-overdue-banner')), findsOneWidget);
      expect(find.text(l.goalOverdueHint), findsOneWidget);

      // "Extend date" opens the edit sheet; the past target date used to
      // make showDatePicker assert (initialDate < firstDate).
      await tester.tap(find.text(l.goalExtendDate));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.event_rounded));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });
  });

  group('health score budgets', () {
    final now = DateTime(2026, 10, 15, 12);

    test('exceeded and active budgets count; ended / upcoming / disabled do not', () {
      Budget b(String status, {String start = '2026-10-01T00:00:00+00:00', String end = '2026-10-31T23:59:59+00:00', bool isActive = true}) =>
          Budget.fromJson(_budgetJson(status: status, start: start, end: end, isActive: isActive));

      expect(b('exceeded').countsTowardHealthScore(now), isTrue);
      expect(b('active').countsTowardHealthScore(now), isTrue);
      // Window contains today even though the stored status lags behind.
      expect(b('upcoming').countsTowardHealthScore(now), isTrue);
      expect(b('upcoming', start: '2026-11-01T00:00:00+00:00', end: '2026-11-30T23:59:59+00:00').countsTowardHealthScore(now), isFalse);
      expect(b('completed', start: '2026-09-01T00:00:00+00:00', end: '2026-09-30T23:59:59+00:00').countsTowardHealthScore(now), isFalse);
      expect(b('exceeded', isActive: false).countsTowardHealthScore(now), isFalse);
    });
  });

  group('session expiry only for the current token', () {
    setUp(() => ApiService.onSessionExpired = null);
    tearDown(() => ApiService.onSessionExpired = null);

    http.Request req(String token, {String path = '/api/transactions'}) =>
        http.Request('GET', Uri.parse('https://x.test$path'))..headers['Authorization'] = 'Bearer $token';

    test('a late 401 for an older token is ignored', () async {
      SharedPreferences.setMockInitialValues({'access_token': 'fresh-1'});
      final calls = <String>[];
      ApiService.onSessionExpired = calls.add;

      await ApiService.checkSessionInvalidated(req('stale-1'), 401, '{}');
      expect(calls, isEmpty);

      await ApiService.checkSessionInvalidated(req('fresh-1'), 401, '{}');
      expect(calls, ['fresh-1']);

      // Deduplicated for the same token; exempt paths never report.
      await ApiService.checkSessionInvalidated(req('fresh-1'), 401, '{}');
      await ApiService.checkSessionInvalidated(req('fresh-1', path: '/api/auth/fcm-token'), 401, '{}');
      expect(calls, ['fresh-1']);
    });

    test('unverified 403 reports, other 403s do not', () async {
      SharedPreferences.setMockInitialValues({'access_token': 'fresh-2'});
      final calls = <String>[];
      ApiService.onSessionExpired = calls.add;
      await ApiService.checkSessionInvalidated(req('fresh-2'), 403, '{"detail":"Forbidden"}');
      expect(calls, isEmpty);
      await ApiService.checkSessionInvalidated(req('fresh-2'), 403, '{"detail":"Email not verified"}');
      expect(calls, ['fresh-2']);
    });

    test('handleSessionExpired only removes the matching token', () async {
      SharedPreferences.setMockInitialValues({'access_token': 'new'});
      final auth = AuthProvider();
      expect(await auth.handleSessionExpired('old'), isFalse);
      expect(await ApiService.getToken(), 'new');

      await auth.handleSessionExpired('new');
      expect(await ApiService.getToken(), isNull);
    });
  });

  group('auth check vs logout', () {
    test('logout clears isAuthChecking synchronously', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthProvider();
      expect(auth.isAuthChecking, isTrue); // startup state
      final done = auth.logout();
      expect(auth.isAuthChecking, isFalse);
      await done;
    });
  });

  group('refreshUserSilently', () {
    test('is a no-op that does not throw or notify when signed out', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthProvider();
      var notified = 0;
      auth.addListener(() => notified++);
      await auth.refreshUserSilently();
      expect(auth.isAuthenticated, isFalse);
      expect(notified, 0);
    });
  });

  group('pending FCM unregister', () {
    test('round-trips and is only cleared by its own auth token', () async {
      SharedPreferences.setMockInitialValues({});
      await PendingFcmUnregister.save(
        const PendingFcmUnregister(authToken: 'a1', userId: 'u1', fcmToken: 'f1'),
      );
      final loaded = await PendingFcmUnregister.load();
      expect(loaded?.authToken, 'a1');
      expect(loaded?.userId, 'u1');
      expect(loaded?.fcmToken, 'f1');

      await PendingFcmUnregister.clearIfAuthToken('other');
      expect(await PendingFcmUnregister.load(), isNotNull);
      await PendingFcmUnregister.clearIfAuthToken('a1');
      expect(await PendingFcmUnregister.load(), isNull);
    });
  });

  group('response body timeout', () {
    test('a body that stalls mid-way times out', () async {
      final controller = StreamController<List<int>>();
      controller.add([1, 2, 3]); // ...and then nothing more.
      await expectLater(
        readBodyWithTimeout(controller.stream, const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );
      await controller.close();
    });

    test('a complete body is returned', () async {
      final bytes = await readBodyWithTimeout(
        Stream.fromIterable([
          [1, 2],
          [3],
        ]),
        const Duration(seconds: 1),
      );
      expect(bytes, [1, 2, 3]);
    });
  });

  group('add transaction amount display', () {
    Future<void> pumpAt360x640(WidgetTester tester, {double textScale = 1.0}) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2.0;
      tester.view.padding = const FakeViewPadding(top: 48, bottom: 96);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_addTransactionApp());
      await tester.pumpAndSettle();
    }

    Future<void> typeDigits(WidgetTester tester, String digits) async {
      for (final d in digits.split('')) {
        final key = find.byKey(ValueKey('keypad-$d'));
        await tester.ensureVisible(key);
        await tester.pumpAndSettle();
        await tester.tap(key);
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    void expectAmountFits(WidgetTester tester) {
      expect(tester.takeException(), isNull);
      final box = tester.getRect(find.byKey(const ValueKey('amount-display')));
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(360));
    }

    testWidgets('12 digits never overflow at text scale 1.0', (tester) async {
      await pumpAt360x640(tester);
      await typeDigits(tester, '999999999999');
      expect(find.text('999,999,999,999'), findsOneWidget);
      expectAmountFits(tester);
    });

    testWidgets('12 digits never overflow at text scale 2.0', (tester) async {
      await pumpAt360x640(tester, textScale: 2.0);
      await typeDigits(tester, '888888888888');
      expect(find.text('888,888,888,888'), findsOneWidget);
      expectAmountFits(tester);
    });

    test('pinned-header threshold grows with the text scale', () {
      final at1 = pinnedHeaderMinHeight(TextScaler.noScaling);
      final at2 = pinnedHeaderMinHeight(const TextScaler.linear(2.0));
      // ≈460 dp at 1.0 (fits a 360×640 phone's ~512 dp body) ...
      expect(at1, closeTo(460, 10));
      expect(at1, lessThan(512));
      // ... but at 2.0 the header + keypad no longer fit: scroll everything.
      expect(at2, greaterThan(512));
    });

    testWidgets('keypad uses the available width in landscape with insets', (tester) async {
      SharedPreferences.setMockInitialValues({});
      // 640x360 landscape with a 48 dp side inset (nav bar / cutout).
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 2.0;
      tester.view.padding = const FakeViewPadding(left: 96, top: 48);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_addTransactionApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final key3 = tester.getRect(find.byKey(const ValueKey('keypad-3')));
      expect(key3.right, lessThanOrEqualTo(640 - 16 + 0.5));
    });
  });
}
