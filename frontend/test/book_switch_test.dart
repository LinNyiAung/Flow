import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/book_session.dart';
import 'package:frontend/providers/budget_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/insight_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/ai/ai_chat_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/transactions/transactions_list_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/book_switch.dart';
import 'package:frontend/widgets/read_only_banner.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// HTTP: ONE MockClient for the file (ApiService binds its inner client once).
// ---------------------------------------------------------------------------

late Future<http.Response> Function(http.Request) _respond;
final List<http.Request> _requests = [];
final _mock = MockClient((request) {
  _requests.add(request);
  return _respond(request);
});

Future<T> _run<T>(Future<T> Function() call) => http.runWithClient(call, () => _mock);

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _overview({bool readOnly = false}) => {
      'family': {'id': 'f1', 'name': 'Aung family', 'read_only': readOnly},
      'me': {'member_id': 'm1', 'role': 'owner'},
      'members': [
        {'id': 'm1', 'display_name': 'Dad', 'kind': 'account', 'role': 'owner', 'status': 'active', 'is_me': true},
      ],
      'invites': [],
      'limits': {'max_members': 6, 'max_placeholders': 20},
    };

Map<String, dynamic> _txJson(String id) => {
      'id': id,
      'user_id': 'u1',
      'type': 'outflow',
      'main_category': 'Food',
      'sub_category': 'Groceries',
      'date': '2026-11-10T00:00:00Z',
      'description': null,
      'amount': 60000,
      'currency': 'mmk',
      'created_at': '2026-11-10T01:00:00Z',
      'updated_at': '2026-11-10T01:00:00Z',
    };

// ---------------------------------------------------------------------------
// Fakes for Home.
// ---------------------------------------------------------------------------

class _FakeTransactions extends TransactionProvider {
  int fetches = 0;
  @override
  List<Transaction> get transactions => const [];
  @override
  List<Transaction> get weekOutflows => const [];
  @override
  Balance? get balance => Balance(
        currency: Currency.mmk,
        balance: 2500000,
        availableBalance: 2000000,
        allocatedToGoals: 500000,
        totalInflow: 3000000,
        totalOutflow: 500000,
      );
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchTransactions(
      {int? limit, int? skip, TransactionType? type, DateTime? startDate, DateTime? endDate, Currency? currency}) async {
    fetches++;
  }

  @override
  Future<void> fetchWeekSpending({DateTime? today}) async {}
  @override
  Future<void> fetchBalance({Currency? currency}) async {}
}

class _FakeBudgets extends BudgetProvider {
  @override
  List<Budget> get activeBudgets => const [];
  @override
  Future<void> fetchBudgets({bool activeOnly = false, BudgetPeriod? period, Currency? currency}) async {}
}

class _FakeGoals extends GoalProvider {
  @override
  List<Goal> get activeGoals => const [];
  @override
  Future<void> fetchGoals({GoalStatus? statusFilter, Currency? currency}) async {}
  @override
  Future<void> fetchSummary({Currency? currency}) async {}
}

class _FakeChat extends ChatProvider {
  @override
  Future<void> loadChatHistory() async {}
}

class _FakeNotifications extends NotificationProvider {
  @override
  Future<void> fetchUnreadCount() async {}
}

/// A family that is already known (no server).
class _FakeFamily extends FamilyProvider {
  _FakeFamily({this.member = true, this.name = 'Aung family', this.readOnlyFlag = false, this.owner = true});

  final bool member;
  final String name;
  final bool readOnlyFlag;
  final bool owner;

  @override
  Family? get family => member ? Family(id: 'f1', name: name, readOnly: readOnlyFlag) : null;
  @override
  bool get inFamily => member;
  @override
  bool get readOnly => member && readOnlyFlag;
  @override
  bool get isOwner => member && owner;
  @override
  bool get isAdmin => isOwner;
  @override
  bool get loaded => true;
  @override
  Future<void> refresh() async {}
}

const _longEnName = 'The Aung Thu Win and Daw Khin Myat family of Yangon';
const _longMyName = 'ဦးအောင်သူဝင်းနှင့် ဒေါ်ခင်မြတ်တို့ ရန်ကုန်မိသားစု';

late ThemeData _light;
late ThemeData _dark;

/// Home under a key that follows the mode, as AuthWrapper does, so a switch
/// rebuilds it.
Future<_FakeTransactions> _pumpHome(
  WidgetTester tester, {
  FamilyProvider? family,
  BookModeProvider? books,
  Locale locale = const Locale('en'),
  double width = 360,
  double height = 1400,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final transactions = _FakeTransactions();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<TransactionProvider>.value(value: transactions),
      ChangeNotifierProvider<BudgetProvider>(create: (_) => _FakeBudgets()),
      ChangeNotifierProvider<GoalProvider>(create: (_) => _FakeGoals()),
      ChangeNotifierProvider<ChatProvider>(create: (_) => _FakeChat()),
      ChangeNotifierProvider<InsightProvider>(create: (_) => InsightProvider()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => _FakeNotifications()),
      ChangeNotifierProvider<PlanProvider>(create: (_) => PlanProvider()),
      if (family != null) ChangeNotifierProvider<FamilyProvider>.value(value: family),
      if (books != null) ChangeNotifierProvider<BookModeProvider>.value(value: books),
    ],
    child: MaterialApp(
      locale: locale,
      theme: _light,
      darkTheme: _dark,
      themeMode: themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('my')],
      routes: {'/subscription': (_) => const Scaffold(body: Text('plans screen'))},
      home: books == null
          ? const HomeScreen()
          : Consumer<BookModeProvider>(
              builder: (_, b, __) => HomeScreen(key: ValueKey('home-${b.mode.name}')),
            ),
    ),
  ));
  await tester.pumpAndSettle();
  return transactions;
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu_rounded));
  await tester.pumpAndSettle();
}

/// [finder] lies inside the screen, left to right.
void _expectOnScreen(WidgetTester tester, Finder finder, double width) {
  for (final element in finder.evaluate()) {
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(width + 0.01));
  }
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Building a theme starts Manrope loads that can't succeed offline.
    runZonedGuarded(() {
      _light = AppTheme.light;
      _dark = AppTheme.dark;
    }, (error, _) {
      if (!'$error'.contains('Manrope')) throw error;
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // ApiService binds its inner client on first use: make it the mock.
    SharedPreferences.setMockInitialValues({});
    _respond = (_) async => _json({'family': null});
    await _run(() => ApiService.getFamily());
  });

  setUp(() {
    _respond = (_) async => _json([]);
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
    ApiService.bookMode = BookMode.personal;
    ApiService.onNoFamily = null;
    _requests.clear();
  });
  tearDown(() {
    ApiService.bookMode = BookMode.personal;
    ApiService.onNoFamily = null;
  });

  final en = AppLocalizations(const Locale('en'));
  final my = AppLocalizations(const Locale('my'));

  group('the switch', () {
    testWidgets('not in a family: no switch on Home or in the menu, and no banner', (tester) async {
      await _pumpHome(tester, family: _FakeFamily(member: false), books: BookModeProvider());
      expect(find.byKey(BookSwitch.personalKey), findsNothing);
      expect(find.byKey(BookSwitch.familyKey), findsNothing);
      expect(find.byType(ReadOnlyBanner), findsNothing);
      expect(find.text(en.familyReadOnlyBanner), findsNothing);

      await _openDrawer(tester);
      expect(find.byKey(BookSwitch.personalKey), findsNothing);
    });

    testWidgets('no family providers at all (older screens and tests): Home as today', (tester) async {
      await _pumpHome(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(BookSwitch.personalKey), findsNothing);
      expect(find.text(en.availableToSpend), findsOneWidget);
    });

    testWidgets('in a family: Personal and the family name; tapping Family switches and rebuilds Home',
        (tester) async {
      final books = BookModeProvider();
      final transactions = await _pumpHome(tester, family: _FakeFamily(), books: books);

      expect(find.byKey(BookSwitch.personalKey), findsOneWidget);
      expect(find.byKey(BookSwitch.familyKey), findsOneWidget);
      expect(find.text(en.bookPersonal), findsOneWidget);
      expect(find.text('Aung family'), findsOneWidget);
      expect(tester.getSemantics(find.byKey(BookSwitch.personalKey)), containsSemantics(isSelected: true));
      expect(tester.getSemantics(find.byKey(BookSwitch.familyKey)), containsSemantics(isSelected: false));
      // The switch comes before the hero.
      expect(tester.getRect(find.byKey(BookSwitch.familyKey)).bottom,
          lessThan(tester.getRect(find.text(en.availableToSpend)).top));
      expect(transactions.fetches, 1);

      await tester.tap(find.byKey(BookSwitch.familyKey));
      await tester.pumpAndSettle();

      expect(books.mode, BookMode.family);
      expect(ApiService.bookMode, BookMode.family);
      expect(transactions.fetches, 2, reason: 'Home was rebuilt and loaded the family book');
      expect(tester.getSemantics(find.byKey(BookSwitch.familyKey)), containsSemantics(isSelected: true));

      // Tapping the selected segment does nothing.
      await tester.tap(find.byKey(BookSwitch.familyKey));
      await tester.pumpAndSettle();
      expect(transactions.fetches, 2);

      await tester.tap(find.byKey(BookSwitch.personalKey));
      await tester.pumpAndSettle();
      expect(books.mode, BookMode.personal);
      expect(transactions.fetches, 3);
    });

    testWidgets('the side menu has the switch after the profile header, and it switches', (tester) async {
      final books = BookModeProvider();
      await _pumpHome(tester, family: _FakeFamily(), books: books);
      await _openDrawer(tester);

      final inDrawer = find.descendant(of: find.byType(Drawer), matching: find.byKey(BookSwitch.familyKey));
      expect(inDrawer, findsOneWidget);
      // Below the profile header (its avatar letter), above the menu items.
      expect(tester.getRect(inDrawer).top,
          greaterThan(tester.getRect(find.descendant(of: find.byType(Drawer), matching: find.text('U'))).bottom));
      expect(tester.getRect(inDrawer).bottom,
          lessThan(tester.getRect(find.descendant(of: find.byType(Drawer), matching: find.text(en.dashboard))).top));

      await tester.tap(inDrawer);
      await tester.pumpAndSettle();
      expect(books.mode, BookMode.family);
      expect(find.byType(Drawer), findsNothing, reason: 'the menu closes');
    });
  });

  group('which book a screen shows', () {
    testWidgets('bookTitle: the title alone in Personal, "title · family" in Family', (tester) async {
      final books = BookModeProvider();
      final titles = <String>[];
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<FamilyProvider>.value(value: _FakeFamily()),
          ChangeNotifierProvider<BookModeProvider>.value(value: books),
        ],
        child: Builder(builder: (context) {
          titles.add(bookTitle(context, 'Budgets'));
          return const SizedBox();
        }),
      ));
      expect(titles.last, 'Budgets');
      await tester.runAsync(() => books.setMode(BookMode.family));
      await tester.pump();
      expect(titles.last, 'Budgets · Aung family');

      // No family providers in the tree: the title alone.
      titles.clear();
      await tester.pumpWidget(Builder(builder: (context) {
        titles.add(bookTitle(context, 'Budgets'));
        return const SizedBox();
      }));
      expect(titles.single, 'Budgets');
    });

    Future<void> pumpList(WidgetTester tester, BookModeProvider books, Locale locale, String name) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<NotificationProvider>(create: (_) => _FakeNotifications()),
          ChangeNotifierProvider<PlanProvider>(create: (_) => PlanProvider()),
          ChangeNotifierProvider<FamilyProvider>.value(value: _FakeFamily(name: name)),
          ChangeNotifierProvider<BookModeProvider>.value(value: books),
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
          home: TransactionsListScreen(
            initialStartDate: DateTime(2026, 11, 10),
            initialEndDate: DateTime(2026, 11, 10),
            initialCurrency: Currency.mmk,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the transactions list says which book is open', (tester) async {
      final books = BookModeProvider();
      await pumpList(tester, books, const Locale('en'), 'Aung family');
      expect(find.text(en.allTransactionsTitle), findsOneWidget);

      await tester.runAsync(() => books.setMode(BookMode.family));
      await pumpList(tester, books, const Locale('en'), 'Aung family');
      expect(find.text('${en.allTransactionsTitle} · Aung family'), findsOneWidget);
    });

    for (final lang in ['en', 'my']) {
      testWidgets('$lang 360: Ko Toe Pwar\'s bar names the family in Family mode', (tester) async {
        final l = AppLocalizations(Locale(lang));
        final books = BookModeProvider();
        Future<void> open() async {
          tester.view.physicalSize = const Size(360 * 3, 800 * 3);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<ChatProvider>(create: (_) => _FakeChat()),
              ChangeNotifierProvider<PlanProvider>(
                  create: (_) => PlanProvider(loader: () async => PlanStatus(plan: Plan.free))),
              ChangeNotifierProvider<FamilyProvider>.value(value: _FakeFamily(name: lang == 'my' ? _longMyName : _longEnName)),
              ChangeNotifierProvider<BookModeProvider>.value(value: books),
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
              home: AiChatScreen(),
            ),
          ));
          await tester.pump(const Duration(milliseconds: 100));
        }

        await open();
        final bar = find.byType(AppBar);
        expect(find.descendant(of: bar, matching: find.text(l.aiMoneyHelper)), findsOneWidget);

        await tester.runAsync(() => books.setMode(BookMode.family));
        await open();
        expect(tester.takeException(), isNull);
        final name = find.descendant(of: bar, matching: find.textContaining(lang == 'my' ? _longMyName : _longEnName));
        expect(name, findsOneWidget);
        expect(find.descendant(of: bar, matching: find.text(l.aiMoneyHelper)), findsNothing);
        _expectOnScreen(tester, name, 360);
      });
    }

    testWidgets('Myanmar 360, a long family name: the list title still fits the bar', (tester) async {
      final books = BookModeProvider();
      await tester.runAsync(() => books.setMode(BookMode.family));
      await pumpList(tester, books, const Locale('my'), _longMyName);
      expect(tester.takeException(), isNull);
      final title = find.text('${my.allTransactionsTitle} · $_longMyName');
      expect(title, findsOneWidget);
      _expectOnScreen(tester, title, 360);
    });
  });

  group('a read-only family', () {
    Future<BookModeProvider> familyMode(WidgetTester tester) async {
      final books = BookModeProvider();
      await tester.runAsync(() => books.setMode(BookMode.family));
      return books;
    }

    testWidgets('the owner sees the banner with Upgrade; + is disabled and says why', (tester) async {
      final books = await familyMode(tester);
      await _pumpHome(tester, family: _FakeFamily(readOnlyFlag: true), books: books);

      expect(find.text(en.familyReadOnlyBanner), findsOneWidget);
      // The banner sits under the switch and above the hero.
      expect(tester.getRect(find.text(en.familyReadOnlyBanner)).top,
          greaterThan(tester.getRect(find.byKey(BookSwitch.familyKey)).bottom));
      expect(tester.getRect(find.text(en.familyReadOnlyBanner)).bottom,
          lessThan(tester.getRect(find.text(en.availableToSpend)).top));

      final fab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
      expect(fab.tooltip, en.familyReadOnlyBanner);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text(en.manualEntry), findsNothing, reason: 'the add sheet does not open');
      expect(find.descendant(of: find.byType(SnackBar), matching: find.text(en.familyReadOnlyBanner)), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, en.upgrade));
      await tester.pumpAndSettle();
      expect(find.text('plans screen'), findsOneWidget);
    });

    testWidgets('a member sees the banner without Upgrade', (tester) async {
      final books = await familyMode(tester);
      await _pumpHome(tester, family: _FakeFamily(readOnlyFlag: true, owner: false), books: books);
      expect(find.text(en.familyReadOnlyBanner), findsOneWidget);
      expect(find.widgetWithText(FilledButton, en.upgrade), findsNothing);
    });

    testWidgets('in Personal mode the read-only family changes nothing', (tester) async {
      await _pumpHome(tester, family: _FakeFamily(readOnlyFlag: true), books: BookModeProvider());
      expect(find.text(en.familyReadOnlyBanner), findsNothing);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text(en.manualEntry), findsOneWidget);
    });

    testWidgets('a family that is not read-only: no banner, + opens the add sheet', (tester) async {
      final books = await familyMode(tester);
      await _pumpHome(tester, family: _FakeFamily(), books: books);
      expect(find.text(en.familyReadOnlyBanner), findsNothing);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text(en.manualEntry), findsOneWidget);
    });
  });

  group('layout: EN and MY, 360 and 390, light and dark', () {
    for (final locale in const [Locale('en'), Locale('my')]) {
      for (final width in const [360.0, 390.0]) {
        for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
          testWidgets('${locale.languageCode} $width ${mode.name}: the switch fits and the banner wraps',
              (tester) async {
            final l = AppLocalizations(locale);
            final name = locale.languageCode == 'my' ? _longMyName : _longEnName;
            final books = BookModeProvider();
            await tester.runAsync(() => books.setMode(BookMode.family));
            await _pumpHome(tester,
                family: _FakeFamily(name: name, readOnlyFlag: true),
                books: books,
                locale: locale,
                width: width,
                themeMode: mode);
            expect(tester.takeException(), isNull);

            _expectOnScreen(tester, find.byKey(BookSwitch.personalKey), width);
            _expectOnScreen(tester, find.byKey(BookSwitch.familyKey), width);
            expect(find.text(l.bookPersonal), findsOneWidget);
            final personalLabel = tester.renderObject<RenderParagraph>(find.text(l.bookPersonal));
            expect(personalLabel.didExceedMaxLines, isFalse, reason: '"Personal" is shown in full');

            final banner = find.text(l.familyReadOnlyBanner);
            expect(banner, findsOneWidget);
            expect(tester.renderObject<RenderParagraph>(banner).didExceedMaxLines, isFalse);
            _expectOnScreen(tester, banner, width);
            _expectOnScreen(tester, find.widgetWithText(FilledButton, l.upgrade), width);

            await _openDrawer(tester);
            expect(tester.takeException(), isNull);
            _expectOnScreen(tester, find.descendant(of: find.byType(Drawer), matching: find.byKey(BookSwitch.familyKey)),
                width);
          });
        }
      }
    }
  });

  group('Review Focus 2: a late answer from the other book', () {
    test('a personal fetchTransactions answer that arrives after the switch to Family is dropped', () async {
      final transactions = TransactionProvider();
      final books = BookModeProvider();
      final session = BookSession(
        books: books,
        family: FamilyProvider(),
        navigatorKey: GlobalKey<NavigatorState>(),
        resetBookData: transactions.reset,
        showMessage: (_) {},
        noLongerMemberText: () => '',
      )..attach();
      addTearDown(session.detach);

      final personalGate = Completer<http.Response>();
      _respond = (r) async {
        if (r.url.path == '/api/transactions') {
          if (r.headers['X-Book'] == 'family') return _json([_txJson('family-1')]);
          return personalGate.future;
        }
        return _json({});
      };

      await _run(() async {
        final personal = transactions.fetchTransactions(limit: 30);
        await pumpEventQueue();
        expect(_requests.single.headers['X-Book'], isNull);

        await books.setMode(BookMode.family); // the switch: reset, Home rebuilt
        await transactions.fetchTransactions(limit: 30); // the new Home's fetch
        expect(transactions.transactions.map((t) => t.id), ['family-1']);

        personalGate.complete(_json([_txJson('personal-1')]));
        await personal;
        await pumpEventQueue();
      });
      expect(transactions.transactions.map((t) => t.id), ['family-1'],
          reason: 'the late personal answer must not fill the family screens');
      expect(transactions.isLoading, isFalse);
    });

    test('and the reverse: a late family answer after switching back to Personal is dropped', () async {
      final transactions = TransactionProvider();
      final books = BookModeProvider();
      final session = BookSession(
        books: books,
        family: FamilyProvider(),
        navigatorKey: GlobalKey<NavigatorState>(),
        resetBookData: transactions.reset,
        showMessage: (_) {},
        noLongerMemberText: () => '',
      )..attach();
      addTearDown(session.detach);
      await books.setMode(BookMode.family);

      final familyGate = Completer<http.Response>();
      _respond = (r) async {
        if (r.url.path == '/api/transactions') {
          if (r.headers['X-Book'] == 'family') return familyGate.future;
          return _json([_txJson('personal-1')]);
        }
        return _json({});
      };

      await _run(() async {
        final family = transactions.fetchTransactions(limit: 30);
        await pumpEventQueue();
        await books.setMode(BookMode.personal);
        await transactions.fetchTransactions(limit: 30);
        familyGate.complete(_json([_txJson('family-1')]));
        await family;
        await pumpEventQueue();
      });
      expect(transactions.transactions.map((t) => t.id), ['personal-1']);
    });
  });

  group('a failed family request is not "no family"', () {
    late BookModeProvider books;
    late FamilyProvider family;
    late BookSession session;

    setUp(() {
      SharedPreferences.setMockInitialValues({'access_token': 'tok', BookModeProvider.prefsKeyFor('a'): 'family'});
      books = BookModeProvider();
      family = FamilyProvider();
      session = BookSession(
        books: books,
        family: family,
        navigatorKey: GlobalKey<NavigatorState>(),
        resetBookData: () {},
        showMessage: (_) {},
        noLongerMemberText: () => '',
        familyRetryDelays: const [Duration(milliseconds: 30)],
      )..attach();
    });
    tearDown(() => session.detach());

    int familyCalls() => _requests.where((r) => r.url.path == '/api/family').length;

    test('a 502 at sign-in keeps the remembered Family, retries, and applies it once the family answers', () async {
      var failing = true;
      _respond = (r) async {
        if (r.url.path == '/api/family') {
          return failing ? http.Response('<html>Bad gateway</html>', 502) : _json(_overview());
        }
        return _json([]);
      };
      await _run(() async {
        session.signedIn('a');
        await pumpEventQueue();
        expect(books.mode, BookMode.personal);
        expect(family.loaded, isFalse);
        expect(familyCalls(), 1);

        failing = false;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await pumpEventQueue();
      });
      expect(familyCalls(), 2, reason: 'one retry, then no more once the family is known');
      expect(books.mode, BookMode.family);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(BookModeProvider.prefsKeyFor('a')), 'family');
    });

    test('a network error keeps retrying (with the last delay) until it works', () async {
      var failuresLeft = 3;
      _respond = (r) async {
        if (r.url.path == '/api/family') {
          if (failuresLeft > 0) {
            failuresLeft--;
            throw http.ClientException('offline');
          }
          return _json(_overview());
        }
        return _json([]);
      };
      await _run(() async {
        session.signedIn('a');
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await pumpEventQueue();
      });
      expect(familyCalls(), 4);
      expect(books.mode, BookMode.family);
    });

    test('a 200 without a "family" field is an error, not "no family": the remembered Family is kept', () async {
      var body = <String, dynamic>{};
      _respond = (r) async => r.url.path == '/api/family' ? _json(body) : _json([]);
      await _run(() async {
        session.signedIn('a');
        await pumpEventQueue();
        expect(family.loaded, isFalse);
        expect(family.error, isNotNull);
        expect(books.mode, BookMode.personal);

        body = _overview();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await pumpEventQueue();
      });
      expect(books.mode, BookMode.family);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(BookModeProvider.prefsKeyFor('a')), 'family');
    });

    test('a real {"family": null} answer drops the remembered Family and does not retry', () async {
      _respond = (r) async => r.url.path == '/api/family' ? _json({'family': null}) : _json([]);
      await _run(() async {
        session.signedIn('a');
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await pumpEventQueue();
      });
      expect(family.loaded, isTrue);
      expect(family.inFamily, isFalse);
      expect(books.mode, BookMode.personal);
      expect(familyCalls(), 1);
    });

    test('already in Family mode, a failed refresh keeps Family', () async {
      var failing = false;
      _respond = (r) async {
        if (r.url.path == '/api/family') {
          return failing ? http.Response('oops', 500) : _json(_overview());
        }
        return _json([]);
      };
      await _run(() async {
        session.signedIn('a');
        await pumpEventQueue();
        expect(books.mode, BookMode.family);

        failing = true;
        await family.refresh();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      expect(family.inFamily, isTrue);
      expect(books.mode, BookMode.family);
      expect(familyCalls(), 2, reason: 'nothing to retry: the family is still known');
    });

    test('logout cancels a pending retry', () async {
      _respond = (r) async => r.url.path == '/api/family' ? http.Response('down', 503) : _json([]);
      await _run(() async {
        session.signedIn('a');
        await pumpEventQueue();
        session.reset();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      expect(familyCalls(), 1);
    });
  });
}
