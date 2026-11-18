import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/goal_entry.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/goals/goal_detail_screen.dart';
import 'package:frontend/screens/goals/goal_history_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/money.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// The fake server: GET /api/goals/g1/history pages through [_history] (or
// [_historyTotal] generated entries); everything else answers `{}`.
// ---------------------------------------------------------------------------

final List<http.Request> _requests = [];
List<Map<String, dynamic>>? _history;
int _historyTotal = 0;
int _historyStatus = 200;

List<http.Request> get _historyRequests =>
    _requests.where((r) => r.url.path == '/api/goals/g1/history').toList();

http.Response _json(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

http.Response _historyResponse(http.Request request) {
  if (_historyStatus != 200) return _json({'detail': 'boom'}, _historyStatus);
  final limit = int.parse(request.url.queryParameters['limit']!);
  final offset = int.parse(request.url.queryParameters['offset']!);
  final all = _history ??
      [for (var i = 0; i < _historyTotal; i++) _entry('e$i', 'add', i + 1)];
  final page = all.skip(offset).take(limit).toList();
  return _json({'entries': page, 'total': _history == null ? _historyTotal : all.length});
}

const _at = '2026-11-18T02:44:00+00:00';

Map<String, dynamic> _entry(String id, String kind, num amount, {String at = _at, Map<String, dynamic>? by}) =>
    {'id': id, 'kind': kind, 'amount': amount, 'created_at': at, 'added_by': by};

Map<String, dynamic> _by(String id, String name) => {'member_id': id, 'display_name': name};

// ---------------------------------------------------------------------------
// Providers.
// ---------------------------------------------------------------------------

final _day = DateTime(2026, 11, 1);

Goal _goal() => Goal(
      id: 'g1',
      bookId: 'u1',
      name: 'Holiday',
      targetAmount: 200000,
      currentAmount: 60000,
      goalType: GoalType.savings,
      status: GoalStatus.active,
      progressPercentage: 30,
      createdAt: _day,
      updatedAt: _day,
      currency: Currency.mmk,
    );

class _Goals extends GoalProvider {
  int contributions = 0;
  @override
  Future<bool> contributeToGoal({required String goalId, required double amount}) async {
    contributions++;
    return true;
  }

  @override
  Future<Goal?> getGoal(String goalId) async => _goal();
}

class _Transactions extends TransactionProvider {
  @override
  Future<void> fetchBalance({Currency? currency}) async {}
}

class _Family extends FamilyProvider {
  _Family() {
    debugApply(FamilyOverview(
      family: const Family(id: 'f', name: 'Aung family'),
      myMemberId: 'm1',
      myRole: FamilyMember.roleOwner,
      members: const [
        FamilyMember(id: 'm1', displayName: 'Maya', kind: 'account', role: FamilyMember.roleOwner, isMe: true),
        FamilyMember(
            id: 'm2',
            displayName: 'Aung',
            kind: 'account',
            role: FamilyMember.roleMember,
            status: FamilyMember.statusFormer),
      ],
    ));
  }
  @override
  Future<void> refresh() async {}
}

final _en = AppLocalizations(const Locale('en'));

Future<_Goals> _pump(WidgetTester tester, Widget home,
    {bool family = false, String lang = 'en', double width = 390}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final goals = _Goals();
  BookModeProvider? books;
  if (family) {
    books = BookModeProvider();
    await books.setMode(BookMode.family);
  }
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<GoalProvider>.value(value: goals),
      ChangeNotifierProvider<TransactionProvider>(create: (_) => _Transactions()),
      if (family) ChangeNotifierProvider<FamilyProvider>(create: (_) => _Family()),
      if (books != null) ChangeNotifierProvider<BookModeProvider>.value(value: books),
    ],
    child: MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('my')],
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
  return goals;
}

String _local(String iso) => DateFormat('d MMM, h:mm a').format(DateTime.parse(iso).toLocal());

String _plus(num amount) => '+${formatMoney(amount, Currency.mmk)}';
String _minus(num amount) => '−${formatMoney(amount, Currency.mmk)}';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
    _requests.clear();
    _history = null;
    _historyTotal = 0;
    _historyStatus = 200;
    ApiService.httpClientOverride = MockClient((request) async {
      _requests.add(request);
      if (request.url.path == '/api/goals/g1/history') return _historyResponse(request);
      return _json({});
    });
  });

  tearDown(() {
    ApiService.httpClientOverride = null;
    ApiService.bookMode = BookMode.personal;
  });

  group('parsing', () {
    test('all four kinds, a negative amount, added_by null and set', () {
      final page = GoalHistoryPage.fromJson({
        'entries': [
          _entry('a', 'start', 30000),
          _entry('b', 'add', 50000, by: _by('m1', 'Maya')),
          _entry('c', 'withdraw', -20000.5),
          _entry('d', 'carried_over', 1000),
        ],
        'total': 14,
      });
      expect(page.total, 14);
      expect([for (final e in page.entries) e.kind], [
        GoalEntryKind.start,
        GoalEntryKind.add,
        GoalEntryKind.withdraw,
        GoalEntryKind.carriedOver,
      ]);
      expect(page.entries[0].id, 'a');
      expect(page.entries[0].addedBy, isNull);
      expect(page.entries[1].addedBy?.memberId, 'm1');
      expect(page.entries[1].addedBy?.displayName, 'Maya');
      expect(page.entries[2].amount, -20000.5);
      expect(page.entries[3].amount, 1000.0);
      expect(page.entries[0].createdAt, DateTime.parse(_at).toLocal());
      expect(page.entries[0].createdAt.isUtc, isFalse);
    });
  });

  group('History section', () {
    testWidgets('personal goal: signs, "Started with", local time, no names', (tester) async {
      const addAt = '2026-11-18T02:44:00+00:00';
      _history = [
        // A name the server would not send in a personal book: still not shown.
        _entry('a', 'add', 50000, at: addAt, by: _by('m1', 'Maya')),
        _entry('w', 'withdraw', -20000, at: '2026-11-12T11:32:00+00:00'),
        _entry('s', 'start', 30000, at: '2026-11-01T13:35:00+00:00'),
      ];
      await _pump(tester, GoalDetailScreen(goal: _goal()));

      expect(find.text(_en.goalHistory), findsOneWidget);
      expect(find.text(_plus(50000)), findsOneWidget);
      expect(find.text(_minus(20000)), findsOneWidget);
      expect(find.text(_plus(30000)), findsOneWidget);
      expect(find.text(_en.goalEntryStartedWith), findsOneWidget);
      expect(find.text(_local(addAt)), findsOneWidget);
      expect(find.textContaining('Maya'), findsNothing);
      expect(find.textContaining(_en.goalHistoryShowAll(3)), findsNothing);
      expect(_historyRequests.single.url.queryParameters, {'limit': '10', 'offset': '0'});
    });

    testWidgets('family goal: the adder, and a former member marked', (tester) async {
      _history = [
        _entry('a', 'add', 50000, by: _by('m1', 'Maya')),
        _entry('w', 'withdraw', -20000, by: _by('m2', 'Aung')),
        _entry('s', 'start', 30000, by: _by('m1', 'Maya')),
      ];
      await _pump(tester, GoalDetailScreen(goal: _goal()), family: true);

      expect(find.text('Maya'), findsOneWidget);
      expect(find.text(_en.familyFormerName('Aung')), findsOneWidget);
      expect(find.text('${_en.goalEntryStartedWith} · Maya'), findsOneWidget);
    });

    testWidgets('carried over: its label, no date and no name', (tester) async {
      const at = '2026-11-18T05:00:00+00:00';
      _history = [_entry('c', 'carried_over', 60000, at: at, by: _by('m1', 'Maya'))];
      await _pump(tester, GoalDetailScreen(goal: _goal()), family: true);

      expect(find.text(_en.goalEntryCarriedOver), findsOneWidget);
      expect(find.text(_plus(60000)), findsOneWidget);
      expect(find.text(_local(at)), findsNothing);
      expect(find.textContaining('Maya'), findsNothing);
    });

    testWidgets('more than 10: "Show all (14)" opens the Goal history screen', (tester) async {
      _historyTotal = 14;
      await _pump(tester, GoalDetailScreen(goal: _goal()));

      final showAll = find.text(_en.goalHistoryShowAll(14));
      expect(showAll, findsOneWidget);
      expect(find.text(_plus(10)), findsOneWidget, reason: 'the latest 10 rows');
      expect(find.text(_plus(11)), findsNothing);
      await tester.ensureVisible(showAll);
      await tester.pumpAndSettle();
      await tester.tap(showAll);
      await tester.pumpAndSettle();

      expect(find.byType(GoalHistoryScreen), findsOneWidget);
      expect(find.text(_en.goalHistoryTitle), findsOneWidget);
    });

    testWidgets('exactly 10: no "Show all"', (tester) async {
      _historyTotal = 10;
      await _pump(tester, GoalDetailScreen(goal: _goal()));
      expect(find.textContaining('Show all'), findsNothing);
      expect(find.text(_plus(10)), findsOneWidget);
    });

    testWidgets('no entries: "No money added yet"', (tester) async {
      await _pump(tester, GoalDetailScreen(goal: _goal()));
      expect(find.text(_en.goalHistoryEmpty), findsOneWidget);
    });

    testWidgets('a failure shows a retry; the rest of the screen still works', (tester) async {
      _historyStatus = 500;
      _history = [_entry('a', 'add', 50000)];
      await _pump(tester, GoalDetailScreen(goal: _goal()));

      expect(find.text(_en.goalHistoryLoadFailed), findsOneWidget);
      expect(find.text(_goal().displayCurrentAmount), findsWidgets);
      expect(find.text(_en.manageFunds), findsOneWidget);

      _historyStatus = 200;
      final retry = find.text(_en.tryAgain);
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(find.text(_en.goalHistoryLoadFailed), findsNothing);
      expect(find.text(_plus(50000)), findsOneWidget);
      expect(_historyRequests, hasLength(2));
    });

    testWidgets('a successful Add reloads the history', (tester) async {
      _history = [_entry('a', 'add', 50000)];
      final goals = await _pump(tester, GoalDetailScreen(goal: _goal()));
      expect(_historyRequests, hasLength(1));

      final manage = find.text(_en.manageFunds);
      await tester.ensureVisible(manage);
      await tester.pumpAndSettle();
      await tester.tap(manage);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '5000');
      await tester.tap(find.widgetWithText(ElevatedButton, _en.add));
      await tester.pumpAndSettle();

      expect(goals.contributions, 1);
      expect(_historyRequests, hasLength(2));
    });

    testWidgets('Myanmar at 360 px: every kind fits', (tester) async {
      _history = [
        _entry('a', 'add', 5000000, by: _by('m1', 'Maya Thandar Aung Kyaw')),
        _entry('w', 'withdraw', -2000000, by: _by('m2', 'Aung Aung Kyaw Zin Htet')),
        _entry('s', 'start', 3000000, by: _by('m1', 'Maya Thandar Aung Kyaw')),
        _entry('c', 'carried_over', 1000000),
      ];
      _historyTotal = 4;
      await _pump(tester, GoalDetailScreen(goal: _goal()), family: true, lang: 'my', width: 360);
      expect(tester.takeException(), isNull);
    });
  });

  group('Goal history screen', () {
    testWidgets('pages 50 at a time and stops at the end', (tester) async {
      _historyTotal = 60;
      await _pump(tester, GoalHistoryScreen(goal: _goal()));

      expect(_historyRequests, hasLength(1));
      expect(_historyRequests[0].url.queryParameters, {'limit': '50', 'offset': '0'});

      await tester.drag(find.byType(Scrollable), const Offset(0, -20000));
      await tester.pumpAndSettle();
      expect(_historyRequests, hasLength(2));
      expect(_historyRequests[1].url.queryParameters, {'limit': '50', 'offset': '50'});

      await tester.drag(find.byType(Scrollable), const Offset(0, -20000));
      await tester.pumpAndSettle();
      expect(find.text(_plus(60)), findsOneWidget, reason: 'the last row');
      expect(_historyRequests, hasLength(2), reason: 'no request past the end');
    });
  });
}
