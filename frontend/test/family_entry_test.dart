import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/models/voice_image_models.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/budget_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/insight_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/charts/inflow_analytics_screen.dart';
import 'package:frontend/screens/charts/outflow_analytics_screen.dart';
import 'package:frontend/screens/family/transfer_sheet.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/transactions/add_transaction_screen.dart';
import 'package:frontend/screens/transactions/edit_transaction_screen.dart';
import 'package:frontend/screens/transactions/image_input_screen.dart';
import 'package:frontend/screens/transactions/voice_input_screen.dart';
import 'package:frontend/screens/transactions/transactions_list_screen.dart';
import 'package:frontend/screens/transactions/transfer_detail_view.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/date_format.dart';
import 'package:frontend/utils/family_entries.dart';
import 'package:frontend/utils/money.dart';
import 'package:frontend/widgets/app_bar_save_button.dart';
import 'package:frontend/widgets/app_bar_title.dart';
import 'package:frontend/widgets/for_whom_picker.dart';
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

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

http.Response _refusal(int status, String code) => _json({
      'detail': {'code': code, 'message': 'server says $code'}
    }, status);

Map<String, dynamic> _txJson({
  String id = 't-new',
  String type = 'outflow',
  List<String> forWhom = const [],
  Map<String, dynamic>? addedBy,
}) =>
    {
      'id': id,
      'book_id': 'u1',
      'type': type,
      'main_category': 'Food & Daily Living',
      'sub_category': 'Restaurants',
      'date': '2026-11-10T12:00:00Z',
      'description': null,
      'amount': 12,
      'currency': 'usd',
      'created_at': '2026-11-10T12:00:00Z',
      'updated_at': '2026-11-10T12:00:00Z',
      'for_whom': forWhom,
      'added_by': addedBy,
    };

/// Answers the requests the add / edit screens and the transfer sheet make.
/// [transfer] answers `POST /api/transfers`, [undo] `DELETE /api/transfers/*`.
Future<http.Response> Function(http.Request) _server({
  http.Response Function()? transfer,
  http.Response Function()? undo,
}) {
  return (request) async {
    final path = request.url.path;
    if (path == '/api/transactions/batch-create' && request.method == 'POST') {
      return _json([_txJson()]);
    }
    if (path == '/api/transactions' && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _json(_txJson(forWhom: List<String>.from(body['for_whom'] as List? ?? const [])));
    }
    if (path.startsWith('/api/transactions/') && request.method == 'PUT') {
      return _json(_txJson(id: path.split('/').last));
    }
    if (path.startsWith('/api/categories/')) {
      return _json([
        {
          'main_category': 'Food & Daily Living',
          'sub_categories': ['Restaurants', 'Groceries'],
        }
      ]);
    }
    if (path == '/api/dashboard/balance') {
      final one = {'currency': 'usd', 'balance': 0, 'available_balance': 0};
      return _json(request.url.queryParameters.containsKey('currency') ? one : {'balances': {'usd': one}});
    }
    if (path == '/api/transfers' && request.method == 'POST') {
      return transfer?.call() ??
          _json({'transfer_id': 'tr1', 'personal_transaction_id': 'a', 'family_transaction_id': 'b'});
    }
    if (path.startsWith('/api/transfers/') && request.method == 'DELETE') {
      return undo?.call() ?? _json({'message': 'Transfer undone', 'transfer_id': 'tr1'});
    }
    if (path == '/api/transactions') return _json([]);
    return _json({});
  };
}

Iterable<http.Request> _sent(String method, String pathPrefix) =>
    _requests.where((r) => r.method == method && r.url.path.startsWith(pathPrefix));

Map<String, dynamic> _bodyOf(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

// ---------------------------------------------------------------------------
// Data and fakes.
// ---------------------------------------------------------------------------

/// Me (m1, [role]), Mum (m2, admin or owner), Ko Ko (m3, member), Ma Ma
/// (p1, a placeholder) and Uncle (f1, a former member).
FamilyOverview _overview({String role = FamilyMember.roleMember, bool readOnly = false, String name = 'Aung family'}) =>
    FamilyOverview(
      family: Family(id: 'f', name: name, readOnly: readOnly),
      myMemberId: 'm1',
      myRole: role,
      members: [
        FamilyMember(id: 'm1', displayName: 'Dad', kind: 'account', role: role, isMe: true),
        FamilyMember(id: 'm2', displayName: 'Mum', kind: 'account', role: role == 'owner' ? 'admin' : 'owner'),
        const FamilyMember(id: 'm3', displayName: 'Ko Ko', kind: 'account', role: 'member'),
        const FamilyMember(id: 'p1', displayName: 'Ma Ma', kind: 'placeholder'),
        const FamilyMember(id: 'f1', displayName: 'Uncle', kind: 'account', role: 'member', status: 'former'),
      ],
    );

class _Family extends FamilyProvider {
  _Family([FamilyOverview overview = FamilyOverview.none]) {
    debugApply(overview);
  }
  @override
  Future<void> refresh() async {}
}

Future<BookModeProvider> _books(BookMode mode) async {
  final books = BookModeProvider();
  await books.setMode(mode);
  return books;
}

Transaction _entry({
  String id = 't1',
  TransactionType type = TransactionType.outflow,
  FamilyMemberRef? addedBy,
  List<String> forWhom = const [],
  String? transferId,
  String? description,
}) {
  final d = DateTime(2026, 11, 10, 12);
  return Transaction(
    id: id,
    bookId: 'u1',
    type: type,
    mainCategory: transferId == null ? 'Food & Daily Living' : 'Transfer',
    subCategory: transferId == null ? 'Restaurants' : 'Family wallet',
    date: d,
    description: description,
    amount: transferId == null ? 12 : 50000,
    currency: transferId == null ? Currency.usd : Currency.mmk,
    createdAt: d,
    updatedAt: d,
    addedBy: addedBy,
    forWhom: forWhom,
    transferId: transferId,
  );
}

const _byMe = FamilyMemberRef(memberId: 'm1', displayName: 'Dad');
const _byMum = FamilyMemberRef(memberId: 'm2', displayName: 'Mum');
const _byUncle = FamilyMemberRef(memberId: 'f1', displayName: 'Uncle');

late ThemeData _light;
late ThemeData _dark;

final _en = AppLocalizations(const Locale('en'));
final _my = AppLocalizations(const Locale('my'));

/// A host screen with an "open" button that pushes [screen]; the pushed
/// route's result goes to [onResult].
Future<TransactionProvider> _pump(
  WidgetTester tester,
  Widget Function(BuildContext) screen, {
  FamilyProvider? family,
  BookModeProvider? books,
  TransactionProvider? transactions,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 844),
  void Function(Object?)? onResult,
  bool open = true,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final txs = transactions ?? TransactionProvider();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<TransactionProvider>.value(value: txs),
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
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final result = await Navigator.push(context, MaterialPageRoute(builder: screen));
                onResult?.call(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  if (open) {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }
  return txs;
}

Widget _addScreen(BuildContext _) => AddTransactionScreen(
      categoriesLoader: (_) async => [
        Category(mainCategory: 'Food & Daily Living', subCategories: ['Restaurants']),
      ],
    );

Finder _inBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Picks the quick-pick category, types 12 and taps Save.
Future<void> _fillAndSave(WidgetTester tester, AppLocalizations l) async {
  await _tapAndSettle(tester, find.text('Restaurants'));
  for (final key in ['1', '2']) {
    await tester.ensureVisible(find.byKey(ValueKey('keypad-$key')));
    await tester.tap(find.byKey(ValueKey('keypad-$key')));
    await tester.pump();
  }
  await tester.tap(_inBar(find.text(l.save)));
  await tester.pumpAndSettle();
}

/// Opens the transfer sheet over an empty host screen.
Future<void> openSheet(WidgetTester tester, TransferDirection direction,
    {Locale locale = const Locale('en'), ThemeMode themeMode = ThemeMode.light, double width = 390}) async {
  await _pump(
    tester,
    (_) => const SizedBox(),
    family: _Family(_overview()),
    books: BookModeProvider(),
    locale: locale,
    themeMode: themeMode,
    size: Size(width, 800),
    open: false,
  );
  final context = tester.element(find.text('open'));
  unawaited(showTransferSheet(context, direction: direction));
  await tester.pumpAndSettle();
}

/// Opens [screen] above the host and lets it build (the voice screen's
/// pulse animation never settles).
Future<void> openUnsettled(WidgetTester tester, Widget Function(BuildContext) screen,
    {required BookModeProvider books, FamilyOverview? overview}) async {
  await _pump(tester, screen, family: _Family(overview ?? _overview()), books: books, open: false);
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// The review screen's own Save (voice list or receipt).
Future<void> tapSave(WidgetTester tester) async {
  final save = find.widgetWithText(FilledButton, _en.saveTransactionButton);
  await tester.ensureVisible(save);
  await tester.pump();
  await tester.tap(save);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Lets routes, sheets, dialogs and fake requests finish without waiting
/// for the voice screen's endless pulse to settle.
Future<void> _settleSome(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapSome(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settleSome(tester);
}

AppBarSaveButton _saveButton(WidgetTester tester) => tester.widget<AppBarSaveButton>(find.byType(AppBarSaveButton));

IconButton _deleteButton(WidgetTester tester) => tester.widget<IconButton>(
    find.ancestor(of: _inBar(find.byIcon(Icons.delete_outline_rounded)), matching: find.byType(IconButton)));

/// Nothing overflowed, and every element [finder] finds lies on screen.
void _expectFits(WidgetTester tester, Finder finder, double width) {
  expect(tester.takeException(), isNull);
  expect(finder, findsWidgets);
  for (final element in finder.evaluate()) {
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    expect(rect.left, greaterThanOrEqualTo(0), reason: '$finder');
    expect(rect.right, lessThanOrEqualTo(width + 0.01), reason: '$finder');
  }
}

// ---- Home ----

class _HomeTransactions extends TransactionProvider {
  int fetches = 0;
  @override
  List<Transaction> get transactions => [
        _entry(id: 'tr-leg', type: TransactionType.outflow, transferId: 'tr1'),
        _entry(id: 'normal'),
      ];
  @override
  List<Transaction> get weekOutflows => const [];
  @override
  Balance? get balance => null;
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

Future<_HomeTransactions> _pumpHome(
  WidgetTester tester, {
  FamilyProvider? family,
  BookModeProvider? books,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(360 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final transactions = _HomeTransactions();
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
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('my')],
      home: const HomeScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  return transactions;
}

// ---- analytics ----

final _now = DateTime.now();
final _thisMonth = DateTime(_now.year, _now.month, 1, 12);

Transaction _chartTx(TransactionType type, String category, double amount, {String? transferId}) => Transaction(
      id: '$category-$amount',
      bookId: 'u1',
      type: type,
      mainCategory: category,
      subCategory: 'Other',
      date: _thisMonth,
      amount: amount,
      currency: Currency.usd,
      createdAt: _thisMonth,
      updatedAt: _thisMonth,
      transferId: transferId,
    );

Future<List<Transaction>> _chartLoader({
  int limit = 50,
  int skip = 0,
  TransactionType? type,
  DateTime? startDate,
  DateTime? endDate,
  Currency? currency,
}) async =>
    [
      _chartTx(TransactionType.outflow, 'Food & Daily Living', 100),
      _chartTx(TransactionType.outflow, 'Transfer', 500, transferId: 'tr1'),
      _chartTx(TransactionType.inflow, 'Employment Income', 200),
      _chartTx(TransactionType.inflow, 'Transfer', 300, transferId: 'tr2'),
    ].where((t) => type == null || t.type == type).toList();

class _FakeAnalyticsNotifications extends NotificationProvider {
  @override
  Future<void> fetchUnreadCount() async {}
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    runZonedGuarded(() {
      _light = AppTheme.light;
      _dark = AppTheme.dark;
    }, (error, _) {
      if (!'$error'.contains('Manrope')) throw error;
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    SharedPreferences.setMockInitialValues({});
    _respond = (_) async => _json({'family': null});
    await http.runWithClient(() => ApiService.getFamily(), () => _mock);
  });

  setUp(() {
    _respond = _server();
    _requests.clear();
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
    ApiService.bookMode = BookMode.personal;
    ApiService.onNoFamily = null;
  });
  tearDown(() {
    ApiService.bookMode = BookMode.personal;
    ApiService.onNoFamily = null;
  });

  group('New entry: the book', () {
    testWidgets('Family mode: "Adding to: <family>" in the header, not the top bar', (tester) async {
      final books = await _books(BookMode.family);
      await _pump(tester, _addScreen, family: _Family(_overview()), books: books);

      final chip = find.byKey(AddTransactionScreen.bookChipKey);
      expect(chip, findsOneWidget);
      expect(find.descendant(of: chip, matching: find.text(_en.addingToBook('Aung family'))), findsOneWidget);
      expect(_inBar(chip), findsNothing);
      // Above the type toggle.
      expect(tester.getRect(chip).bottom, lessThanOrEqualTo(tester.getRect(find.text(_en.outflow)).top));
    });

    testWidgets('not in a family (or no family providers): no chip, no For whom', (tester) async {
      await _pump(tester, _addScreen, family: _Family(), books: BookModeProvider());
      expect(find.byKey(AddTransactionScreen.bookChipKey), findsNothing);
      expect(find.byKey(ForWhomPicker.rowKey), findsNothing);

      await _pump(tester, _addScreen);
      expect(find.byKey(AddTransactionScreen.bookChipKey), findsNothing);
    });

    testWidgets('Family mode flipped to Personal: sent with no X-Book and no for_whom; the family list is untouched',
        (tester) async {
      final books = await _books(BookMode.family);
      Object? result;
      final txs = await _pump(tester, _addScreen,
          family: _Family(_overview()), books: books, onResult: (r) => result = r);

      expect(find.byKey(ForWhomPicker.rowKey), findsOneWidget);
      await _tapAndSettle(tester, find.byKey(AddTransactionScreen.bookChipKey));
      expect(find.text(_en.addingToBook(_en.bookPersonal)), findsOneWidget);
      expect(find.byKey(ForWhomPicker.rowKey), findsNothing, reason: 'For whom is for the family book only');

      await _fillAndSave(tester, _en);

      final posts = _sent('POST', '/api/transactions').toList();
      expect(posts, hasLength(1));
      expect(posts.single.headers.containsKey('X-Book'), isFalse);
      expect(_bodyOf(posts.single).containsKey('for_whom'), isFalse);
      expect(result, true);
      expect(books.mode, BookMode.family, reason: 'the app stays in Family mode');
      expect(ApiService.bookMode, BookMode.family);
      expect(txs.transactions, isEmpty, reason: 'a personal entry never joins the family list');
      // The current (family) book's balance was refreshed.
      final balance = _sent('GET', '/api/dashboard/balance');
      expect(balance, isNotEmpty);
      expect(balance.every((r) => r.headers['X-Book'] == 'family'), isTrue);
    });

    testWidgets('Personal mode flipped to the family: X-Book family, Whole family sends []', (tester) async {
      await _pump(tester, _addScreen, family: _Family(_overview()), books: BookModeProvider());
      expect(find.text(_en.addingToBook(_en.bookPersonal)), findsOneWidget);
      expect(find.byKey(ForWhomPicker.rowKey), findsNothing);

      await _tapAndSettle(tester, find.byKey(AddTransactionScreen.bookChipKey));
      expect(find.text(_en.addingToBook('Aung family')), findsOneWidget);
      expect(find.byKey(ForWhomPicker.rowKey), findsOneWidget);
      expect(find.descendant(of: find.byKey(ForWhomPicker.rowKey), matching: find.text(_en.wholeFamily)),
          findsOneWidget);

      await _fillAndSave(tester, _en);
      final post = _sent('POST', '/api/transactions').single;
      expect(post.headers['X-Book'], 'family');
      expect(_bodyOf(post)['for_whom'], <String>[]);
      expect(ApiService.bookMode, BookMode.personal);
    });

    testWidgets('a read-only family: Save is refused with the reason', (tester) async {
      await _pump(tester, _addScreen, family: _Family(_overview(readOnly: true)), books: BookModeProvider());
      await _tapAndSettle(tester, find.byKey(AddTransactionScreen.bookChipKey));
      await _fillAndSave(tester, _en);
      expect(_sent('POST', '/api/transactions'), isEmpty);
      expect(find.descendant(of: find.byType(SnackBar), matching: find.text(_en.familyReadOnlyBanner)),
          findsOneWidget);
    });
  });

  group('R20: voice and scan follow the book chip', () {
    final lunch = ExtractedTransactionData(
      type: TransactionType.outflow,
      mainCategory: 'Food & Daily Living',
      subCategory: 'Restaurants',
      date: DateTime(2026, 11, 10, 12),
      amount: 12,
      currency: Currency.usd,
      confidence: 0.9,
    );
    final spoken = MultipleExtractedTransactions(transactions: [lunch], totalCount: 1, overallConfidence: 0.9);

    for (final (from, to) in [(BookMode.personal, BookMode.family), (BookMode.family, BookMode.personal)]) {
      for (final (label, icon) in [('mic', Icons.mic_rounded), ('scan', Icons.document_scanner_rounded)]) {
        testWidgets('${from.name} mode, chip flipped to ${to.name}: $label opens for the ${to.name} book',
            (tester) async {
          final books = await _books(from);
          await _pump(tester, _addScreen, family: _Family(_overview()), books: books);
          await _tapAndSettle(tester, find.byKey(AddTransactionScreen.bookChipKey));

          await tester.tap(_inBar(find.byIcon(icon)));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          final BookMode? book = label == 'mic'
              ? tester.widget<VoiceInputScreen>(find.byType(VoiceInputScreen)).book
              : tester.widget<ImageInputScreen>(find.byType(ImageInputScreen)).book;
          expect(book, to);
          expect(books.mode, from, reason: 'the app stays in its mode');
        });
      }
    }

    testWidgets('voice for the family book from Personal mode: the batch carries X-Book family', (tester) async {
      final books = BookModeProvider();
      await openUnsettled(tester, (_) => VoiceInputScreen(book: BookMode.family, initialExtraction: spoken),
          books: books);
      await tapSave(tester);

      final batch = _sent('POST', '/api/transactions/batch-create').single;
      expect(batch.headers['X-Book'], 'family');
      expect(ApiService.bookMode, BookMode.personal);
      // Only the current (personal) book is reloaded.
      final reloads = _requests.where((r) => r.method == 'GET').toList();
      expect(reloads, isNotEmpty);
      expect(reloads.every((r) => !r.headers.containsKey('X-Book')), isTrue);
    });

    testWidgets('voice: each item shows its date, with the AI\'s note under it', (tester) async {
      final noted = ExtractedTransactionData(
        type: TransactionType.outflow,
        mainCategory: 'Food & Daily Living',
        subCategory: 'Restaurants',
        date: DateTime(2026, 11, 10, 12),
        amount: 12,
        currency: Currency.usd,
        confidence: 0.9,
        reasoning: 'Heard "lunch 12 dollars yesterday"',
      );
      await openUnsettled(
          tester,
          (_) => VoiceInputScreen(
              book: BookMode.personal,
              initialExtraction:
                  MultipleExtractedTransactions(transactions: [noted], totalCount: 1, overallConfidence: 0.9)),
          books: BookModeProvider());
      expect(find.text(AppDates.fullIn(DateTime(2026, 11, 10))), findsOneWidget);
      expect(find.textContaining('lunch 12 dollars yesterday'), findsOneWidget);
    });

    testWidgets('voice: an item the AI is unsure of (under 50%) starts unticked; Save sends only the sure one',
        (tester) async {
      final unsure = ExtractedTransactionData(
        type: TransactionType.outflow,
        mainCategory: 'Transportation',
        subCategory: 'Taxi',
        date: DateTime(2026, 11, 10, 12),
        amount: 99,
        currency: Currency.usd,
        confidence: 0.3,
      );
      await openUnsettled(
          tester,
          (_) => VoiceInputScreen(
              book: BookMode.personal,
              initialExtraction:
                  MultipleExtractedTransactions(transactions: [lunch, unsure], totalCount: 2, overallConfidence: 0.6)),
          books: BookModeProvider());
      await tapSave(tester);
      final body = jsonDecode(_sent('POST', '/api/transactions/batch-create').single.body);
      final sent = (body is List ? body : (body as Map)['transactions']) as List;
      expect(sent.map((t) => (t as Map)['amount']), [12]);
    });

    testWidgets('voice for the personal book from Family mode: no X-Book', (tester) async {
      final books = await _books(BookMode.family);
      await openUnsettled(tester, (_) => VoiceInputScreen(book: BookMode.personal, initialExtraction: spoken),
          books: books);
      await tapSave(tester);

      expect(_sent('POST', '/api/transactions/batch-create').single.headers.containsKey('X-Book'), isFalse);
      expect(ApiService.bookMode, BookMode.family);
      final reloads = _requests.where((r) => r.method == 'GET').toList();
      expect(reloads.every((r) => r.headers['X-Book'] == 'family'), isTrue);
    });

    testWidgets('scan for the family book from Personal mode: X-Book family; the personal list is untouched',
        (tester) async {
      final books = BookModeProvider();
      final txs = TransactionProvider();
      await _pump(tester, (_) => ImageInputScreen(book: BookMode.family, initialExtraction: lunch),
          family: _Family(_overview()), books: books, transactions: txs);
      await tapSave(tester);

      expect(_sent('POST', '/api/transactions').single.headers['X-Book'], 'family');
      expect(txs.transactions, isEmpty);
      expect(ApiService.bookMode, BookMode.personal);
    });

    testWidgets('scan for the personal book from Family mode: no X-Book', (tester) async {
      final books = await _books(BookMode.family);
      await _pump(tester, (_) => ImageInputScreen(book: BookMode.personal, initialExtraction: lunch),
          family: _Family(_overview()), books: books);
      await tapSave(tester);

      expect(_sent('POST', '/api/transactions').single.headers.containsKey('X-Book'), isFalse);
      expect(ApiService.bookMode, BookMode.family);
    });
  });

  group('Ko Toe Pwar\'s entries: corrected in the full form', () {
    // A day in this month, so the date picker (up to a year from now) always
    // shows it and the day after it.
    final now = DateTime.now();
    final day10 = DateTime(now.year, now.month, 10, 12);

    ExtractedTransactionData item({
      String sub = 'Restaurants',
      double amount = 12,
      double confidence = 0.9,
      String? description = 'Lunch at the noodle shop',
      String? reasoning,
    }) =>
        ExtractedTransactionData(
          type: TransactionType.outflow,
          mainCategory: 'Food & Daily Living',
          subCategory: sub,
          date: day10,
          description: description,
          amount: amount,
          currency: Currency.usd,
          confidence: confidence,
          reasoning: reasoning,
        );

    MultipleExtractedTransactions heard(List<ExtractedTransactionData> items) =>
        MultipleExtractedTransactions(transactions: items, totalCount: items.length, overallConfidence: 0.9);

    List<Map<String, dynamic>> batchItems() {
      final body = jsonDecode(_sent('POST', '/api/transactions/batch-create').single.body);
      return [for (final t in (body is List ? body : (body as Map)['transactions']) as List) t as Map<String, dynamic>];
    }

    /// Only the review screens create entries: never the form itself.
    Iterable<http.Request> singleCreates() => _requests.where((r) => r.method == 'POST' && r.url.path == '/api/transactions');

    Finder inForm(Finder f) => find.descendant(of: find.byType(AddTransactionScreen), matching: f);

    /// In the form: Category → Food & Daily Living → [sub].
    Future<void> pickSubCategory(WidgetTester tester, String sub) async {
      await _tapSome(tester, inForm(find.byIcon(Icons.unfold_more_rounded)));
      await _tapSome(tester, find.descendant(of: find.byType(ListTile), matching: find.text('Food & Daily Living')));
      await _tapSome(tester, find.descendant(of: find.byType(ListTile), matching: find.text(sub)));
    }

    Future<void> saveForm(WidgetTester tester) async {
      await tester.tap(_inBar(find.text(_en.save)));
      await _settleSome(tester);
    }

    test('ExtractedTransactionData: copyWith changes only what it is given; for_whom is sent only when chosen', () {
      final original = item(reasoning: 'Heard "lunch"');
      final same = original.copyWith();
      expect(same.toJson(), original.toJson());
      expect(same.reasoning, 'Heard "lunch"');
      expect(same.forWhom, isNull);
      expect(original.toJson().containsKey('for_whom'), isFalse);

      final changed = original.copyWith(
        type: TransactionType.inflow,
        mainCategory: 'Employment Income',
        subCategory: 'Salary',
        date: DateTime(2026, 11, 12, 9),
        description: null,
        amount: 30,
        currency: Currency.mmk,
        confidence: 1.0,
        forWhom: ['m3', 'p1'],
      );
      expect(changed.type, TransactionType.inflow);
      expect(changed.mainCategory, 'Employment Income');
      expect(changed.subCategory, 'Salary');
      expect(changed.date, DateTime(2026, 11, 12, 9));
      expect(changed.description, isNull, reason: 'null clears the description');
      expect(changed.amount, 30);
      expect(changed.currency, Currency.mmk);
      expect(changed.confidence, 1.0);
      expect(changed.reasoning, 'Heard "lunch"', reason: 'kept');
      final json = changed.toJson();
      expect(json['for_whom'], ['m3', 'p1']);
      expect(json['type'], 'inflow');
      expect(json['currency'], 'mmk');
      expect(json['description'], isNull);

      expect(changed.copyWith(forWhom: null).toJson().containsKey('for_whom'), isFalse);
      expect(original.copyWith(forWhom: const <String>[]).toJson()['for_whom'], <String>[]);
    });

    testWidgets('voice: tapping an item opens the form filled in; the corrected item goes back and is saved',
        (tester) async {
      await openUnsettled(tester, (_) => VoiceInputScreen(book: BookMode.personal, initialExtraction: heard([item()])),
          books: BookModeProvider());

      await _tapSome(tester, find.text('Restaurants'));
      expect(find.byType(AddTransactionScreen), findsOneWidget);
      expect(inForm(find.text('Lunch at the noodle shop')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('amount-display')), matching: find.text('12')),
          findsOneWidget);
      expect(inForm(find.text('Restaurants')), findsWidgets);
      expect(inForm(find.textContaining(AppDates.fullIn(day10))), findsOneWidget);
      expect(inForm(find.text(_en.repeatLabel)), findsNothing, reason: 'a draft has no repeat');
      expect(_inBar(find.byIcon(Icons.mic_rounded)), findsNothing, reason: 'no second AI read from a draft');
      expect(_inBar(find.byIcon(Icons.document_scanner_rounded)), findsNothing);

      await pickSubCategory(tester, 'Groceries');
      await _tapSome(tester, inForm(find.textContaining(AppDates.fullIn(day10))));
      await _tapSome(tester, find.descendant(of: find.byType(Dialog), matching: find.text('12')).hitTestable());
      await _tapSome(tester, find.text('OK'));
      await saveForm(tester);

      expect(find.byType(AddTransactionScreen), findsNothing);
      expect(singleCreates(), isEmpty, reason: 'the form never creates the entry itself');
      expect(_sent('POST', '/api/transactions/batch-create'), isEmpty);
      final day12 = DateTime(now.year, now.month, 12);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text(AppDates.fullIn(day12)), findsOneWidget);
      expect(find.text('100%'), findsOneWidget, reason: 'checked by a person');

      await tapSave(tester);
      final sent = batchItems().single;
      expect(sent['sub_category'], 'Groceries');
      expect(sent['main_category'], 'Food & Daily Living');
      expect(sent['description'], 'Lunch at the noodle shop');
      expect(sent['amount'], 12);
      final date = DateTime.parse(sent['date'] as String);
      expect([date.year, date.month, date.day], [day12.year, day12.month, day12.day]);
      expect(sent.containsKey('for_whom'), isFalse, reason: 'a personal entry has nobody to be for');
      expect(singleCreates(), isEmpty);
    });

    testWidgets('voice: closing the form changes nothing', (tester) async {
      await openUnsettled(tester, (_) => VoiceInputScreen(book: BookMode.personal, initialExtraction: heard([item()])),
          books: BookModeProvider());

      await _tapSome(tester, find.text('Restaurants'));
      await pickSubCategory(tester, 'Groceries');
      await _tapSome(tester, _inBar(find.byIcon(Icons.close_rounded)));

      expect(find.byType(AddTransactionScreen), findsNothing);
      expect(find.text('Groceries'), findsNothing);
      expect(find.text('90%'), findsOneWidget);
      await tapSave(tester);
      expect(batchItems().single['sub_category'], 'Restaurants');
      expect(singleCreates(), isEmpty);
    });

    testWidgets('voice: the tick still ticks and unticks without opening the form', (tester) async {
      await openUnsettled(tester, (_) => VoiceInputScreen(book: BookMode.personal, initialExtraction: heard([item()])),
          books: BookModeProvider());

      await _tapSome(tester, find.byIcon(Icons.check_circle_rounded));
      expect(find.byType(AddTransactionScreen), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
      final save = tester.widget<FilledButton>(find.widgetWithText(FilledButton, _en.saveTransactionButton));
      expect(save.onPressed, isNull);

      await _tapSome(tester, find.byIcon(Icons.radio_button_unchecked_rounded));
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('voice: an unsure item corrected in the form comes back ticked and is sent', (tester) async {
      final unsure = item(sub: 'Groceries', amount: 5, confidence: 0.3, description: 'Eggs');
      await openUnsettled(
          tester, (_) => VoiceInputScreen(book: BookMode.personal, initialExtraction: heard([item(), unsure])),
          books: BookModeProvider());
      expect(find.text('30%'), findsOneWidget);

      await _tapSome(tester, find.text('Groceries'));
      expect(inForm(find.text('Eggs')), findsOneWidget);
      await saveForm(tester);

      await tapSave(tester);
      expect(batchItems().map((t) => t['amount']), [12, 5]);
    });

    testWidgets('voice: an item with no amount gets it in the form', (tester) async {
      await openUnsettled(
          tester, (_) => VoiceInputScreen(book: BookMode.personal, initialExtraction: heard([item(amount: 0)])),
          books: BookModeProvider());
      expect(find.text(_en.amountNeededLabel), findsOneWidget);

      await _tapSome(tester, find.text('Restaurants'));
      await saveForm(tester);
      expect(find.byType(AddTransactionScreen), findsOneWidget, reason: 'validated as normal: an amount is needed');
      expect(find.text(_en.validationAmountRequired), findsOneWidget);

      for (final key in ['7', '5']) {
        await tester.tap(find.byKey(ValueKey('keypad-$key')));
        await tester.pump();
      }
      await saveForm(tester);
      expect(find.byType(AddTransactionScreen), findsNothing);
      expect(find.text(_en.amountNeededLabel), findsNothing);
      await tapSave(tester);
      expect(batchItems().single['amount'], 75);
    });

    testWidgets('voice, family book: the people chosen in For whom are sent as for_whom for that item',
        (tester) async {
      final books = await _books(BookMode.family);
      await openUnsettled(
          tester,
          (_) => VoiceInputScreen(
              book: BookMode.family, initialExtraction: heard([item(), item(sub: 'Groceries', description: 'Eggs')])),
          books: books);

      await _tapSome(tester, find.text('Restaurants'));
      expect(inForm(find.byKey(ForWhomPicker.rowKey)), findsOneWidget);
      await _tapSome(tester, find.byKey(ForWhomPicker.rowKey));
      await _tapSome(tester, find.byKey(ForWhomPicker.memberKey('p1')));
      await _tapSome(tester, find.byKey(ForWhomPicker.memberKey('m3')));
      await _tapSome(tester, find.byKey(ForWhomPicker.doneKey));
      await saveForm(tester);

      expect(find.byType(AddTransactionScreen), findsNothing);
      await tapSave(tester);
      final sent = batchItems();
      expect(sent[0]['for_whom'], ['m3', 'p1']);
      expect(sent[1].containsKey('for_whom'), isFalse, reason: 'not chosen: Whole family, as before');
      expect(singleCreates(), isEmpty);
    });

    testWidgets('draft: the book is the review screen\'s; the chip does not switch it', (tester) async {
      await openUnsettled(tester, (_) => VoiceInputScreen(book: BookMode.personal, initialExtraction: heard([item()])),
          books: BookModeProvider());

      await _tapSome(tester, find.text('Restaurants'));
      expect(find.text(_en.addingToBook(_en.bookPersonal)), findsOneWidget);
      await _tapSome(tester, find.byKey(AddTransactionScreen.bookChipKey));
      expect(find.text(_en.addingToBook(_en.bookPersonal)), findsOneWidget);
      expect(find.byKey(ForWhomPicker.rowKey), findsNothing);
    });

    testWidgets('draft in a read-only family: Save is refused as normal and nothing goes back', (tester) async {
      final books = await _books(BookMode.family);
      await openUnsettled(
          tester, (_) => VoiceInputScreen(book: BookMode.family, initialExtraction: heard([item()])),
          books: books, overview: _overview(readOnly: true));

      await _tapSome(tester, find.text('Restaurants'));
      await saveForm(tester);
      expect(find.byType(AddTransactionScreen), findsOneWidget);
      expect(find.descendant(of: find.byType(SnackBar), matching: find.text(_en.familyReadOnlyBanner)),
          findsOneWidget);
      expect(singleCreates(), isEmpty);
    });

    testWidgets('receipt: Edit opens the form filled in; the corrected details are shown and saved',
        (tester) async {
      await _pump(tester, (_) => ImageInputScreen(book: BookMode.personal, initialExtraction: item()),
          family: _Family(_overview()), books: BookModeProvider());

      await _tapAndSettle(tester, find.byKey(ImageInputScreen.editKey));
      expect(find.byType(AddTransactionScreen), findsOneWidget);
      expect(inForm(find.text('Lunch at the noodle shop')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('amount-display')), matching: find.text('12')),
          findsOneWidget);

      await pickSubCategory(tester, 'Groceries');
      await _tapAndSettle(tester, inForm(find.text('Lunch at the noodle shop')));
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
          'Weekly groceries');
      await _tapAndSettle(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text(_en.save)));
      await tester.tap(_inBar(find.text(_en.save)));
      await tester.pumpAndSettle();

      expect(find.byType(AddTransactionScreen), findsNothing);
      expect(singleCreates(), isEmpty, reason: 'the form never creates the entry itself');
      expect(find.text('Food & Daily Living > Groceries'), findsOneWidget);
      expect(find.text('Weekly groceries'), findsOneWidget);

      await tapSave(tester);
      final body = _bodyOf(singleCreates().single);
      expect(body['sub_category'], 'Groceries');
      expect(body['description'], 'Weekly groceries');
      expect(body['amount'], 12);
      expect(body.containsKey('for_whom'), isFalse);
    });

    testWidgets('receipt, family book: For whom chosen in the form is sent', (tester) async {
      final books = await _books(BookMode.family);
      await _pump(tester, (_) => ImageInputScreen(book: BookMode.family, initialExtraction: item()),
          family: _Family(_overview()), books: books);

      await _tapAndSettle(tester, find.byKey(ImageInputScreen.editKey));
      await _tapAndSettle(tester, find.byKey(ForWhomPicker.rowKey));
      await _tapAndSettle(tester, find.byKey(ForWhomPicker.memberKey('m3')));
      await _tapAndSettle(tester, find.byKey(ForWhomPicker.doneKey));
      await tester.tap(_inBar(find.text(_en.save)));
      await tester.pumpAndSettle();

      expect(find.text('Ko Ko'), findsOneWidget);
      await tapSave(tester);
      expect(_bodyOf(singleCreates().single)['for_whom'], ['m3']);
    });

    testWidgets('receipt: closing the form keeps the details as read', (tester) async {
      await _pump(tester, (_) => ImageInputScreen(book: BookMode.personal, initialExtraction: item()),
          family: _Family(_overview()), books: BookModeProvider());

      await _tapAndSettle(tester, find.byKey(ImageInputScreen.editKey));
      await pickSubCategory(tester, 'Groceries');
      await _tapAndSettle(tester, _inBar(find.byIcon(Icons.close_rounded)));

      expect(find.text('Food & Daily Living > Restaurants'), findsOneWidget);
      await tapSave(tester);
      expect(_bodyOf(singleCreates().single)['sub_category'], 'Restaurants');
    });
  });

  group('For whom', () {
    testWidgets('two people: for_whom has both ids; the former member is not offered', (tester) async {
      final books = await _books(BookMode.family);
      await _pump(tester, _addScreen, family: _Family(_overview()), books: books);

      await _tapAndSettle(tester, find.byKey(ForWhomPicker.rowKey));
      expect(find.byType(ForWhomPicker), findsOneWidget);
      expect(find.byKey(ForWhomPicker.memberKey('f1')), findsNothing);
      expect(find.byKey(ForWhomPicker.memberKey('p1')), findsOneWidget, reason: 'placeholders count');
      await _tapAndSettle(tester, find.byKey(ForWhomPicker.memberKey('p1')));
      await _tapAndSettle(tester, find.byKey(ForWhomPicker.memberKey('m3')));
      await _tapAndSettle(tester, find.byKey(ForWhomPicker.doneKey));

      expect(find.descendant(of: find.byKey(ForWhomPicker.rowKey), matching: find.text('Ko Ko, Ma Ma')),
          findsOneWidget);

      await _fillAndSave(tester, _en);
      final post = _sent('POST', '/api/transactions').single;
      expect(post.headers['X-Book'], 'family');
      expect(_bodyOf(post)['for_whom'], ['m3', 'p1']);
    });

    testWidgets('Whole family (the default) sends []; choosing it again clears the people', (tester) async {
      final books = await _books(BookMode.family);
      await _pump(tester, _addScreen, family: _Family(_overview()), books: books);

      await _tapAndSettle(tester, find.byKey(ForWhomPicker.rowKey));
      await _tapAndSettle(tester, find.byKey(ForWhomPicker.memberKey('m2')));
      await _tapAndSettle(tester, find.byKey(ForWhomPicker.wholeFamilyKey));
      await _tapAndSettle(tester, find.byKey(ForWhomPicker.doneKey));

      await _fillAndSave(tester, _en);
      expect(_bodyOf(_sent('POST', '/api/transactions').single)['for_whom'], <String>[]);
    });
  });

  group('Edit: who can change it', () {
    for (final (label, role, addedBy, allowed) in [
      ('a member, someone else\'s entry', FamilyMember.roleMember, _byMum, false),
      ('a member, their own entry', FamilyMember.roleMember, _byMe, true),
      ('an admin, someone else\'s entry', FamilyMember.roleAdmin, _byMum, true),
      ('a member, an entry with no adder', FamilyMember.roleMember, null, false),
      ('the owner, an entry with no adder', FamilyMember.roleOwner, null, true),
    ]) {
      testWidgets('$label: Save and Delete ${allowed ? 'enabled' : 'disabled'}', (tester) async {
        final books = await _books(BookMode.family);
        await _pump(tester, (_) => EditTransactionScreen(transaction: _entry(addedBy: addedBy)),
            family: _Family(_overview(role: role)), books: books);

        expect(_saveButton(tester).onPressed != null, allowed);
        expect(_deleteButton(tester).onPressed != null, allowed);
        expect(find.text(_en.entryNotYoursReason), allowed ? findsNothing : findsOneWidget);
        if (addedBy != null) expect(find.text(_en.addedByName(addedBy.displayName)), findsOneWidget);
      });
    }

    testWidgets('a former member\'s entry says so', (tester) async {
      final books = await _books(BookMode.family);
      await _pump(tester, (_) => EditTransactionScreen(transaction: _entry(addedBy: _byUncle)),
          family: _Family(_overview()), books: books);
      expect(find.text(_en.addedByName(_en.familyFormerName('Uncle'))), findsOneWidget);
    });

    testWidgets('a personal entry: enabled, no "Added by", no For whom', (tester) async {
      await _pump(tester, (_) => EditTransactionScreen(transaction: _entry()),
          family: _Family(_overview()), books: BookModeProvider());
      expect(_saveButton(tester).onPressed, isNotNull);
      expect(_deleteButton(tester).onPressed, isNotNull);
      expect(find.textContaining('Added by'), findsNothing);
      expect(find.byKey(ForWhomPicker.rowKey), findsNothing);
    });

    testWidgets('a read-only family: disabled with the read-only reason', (tester) async {
      final books = await _books(BookMode.family);
      await _pump(tester, (_) => EditTransactionScreen(transaction: _entry(addedBy: _byMe)),
          family: _Family(_overview(readOnly: true)), books: books);
      expect(_saveButton(tester).onPressed, isNull);
      expect(_deleteButton(tester).onPressed, isNull);
      expect(find.text(_en.familyReadOnlyBanner), findsOneWidget);
    });
  });

  group('Edit: For whom', () {
    testWidgets('shows the current tags; unchanged → for_whom is not sent', (tester) async {
      final books = await _books(BookMode.family);
      Object? result;
      await _pump(tester, (_) => EditTransactionScreen(transaction: _entry(addedBy: _byMe, forWhom: ['p1'])),
          family: _Family(_overview()), books: books, onResult: (r) => result = r);

      expect(find.descendant(of: find.byKey(ForWhomPicker.rowKey), matching: find.text('Ma Ma')), findsOneWidget);
      await tester.tap(_inBar(find.text(_en.save)));
      await tester.pumpAndSettle();
      final put = _sent('PUT', '/api/transactions/').single;
      expect(_bodyOf(put).containsKey('for_whom'), isFalse);
      expect(put.headers['X-Book'], 'family');
      expect(result, true);
    });

    testWidgets('changed → for_whom is sent', (tester) async {
      final books = await _books(BookMode.family);
      await _pump(tester, (_) => EditTransactionScreen(transaction: _entry(addedBy: _byMe, forWhom: ['p1'])),
          family: _Family(_overview()), books: books);

      await _tapAndSettle(tester, find.byKey(ForWhomPicker.rowKey));
      await _tapAndSettle(tester, find.byKey(ForWhomPicker.memberKey('m3')));
      await _tapAndSettle(tester, find.byKey(ForWhomPicker.doneKey));
      await tester.tap(_inBar(find.text(_en.save)));
      await tester.pumpAndSettle();
      expect(_bodyOf(_sent('PUT', '/api/transactions/').single)['for_whom'], ['m3', 'p1']);
    });
  });

  group('Transfers', () {
    testWidgets('a family leg I made: read-only view with Undo; no Save, no category', (tester) async {
      final books = await _books(BookMode.family);
      await _pump(
          tester,
          (_) => EditTransactionScreen(
              transaction: _entry(type: TransactionType.inflow, addedBy: _byMe, transferId: 'tr1')),
          family: _Family(_overview()),
          books: books);

      expect(find.byType(TransferDetailView), findsOneWidget);
      expect(find.text(_en.transferToFamily), findsWidgets);
      expect(find.byType(AppBarSaveButton), findsNothing);
      // The category ("Transfer" / "Family wallet") is never shown; the
      // top bar's title is "Transfer" in English.
      final body = find.byType(SingleChildScrollView);
      expect(find.descendant(of: body, matching: find.text('Family wallet')), findsNothing);
      expect(find.descendant(of: body, matching: find.text('Transfer')), findsNothing);
      expect(find.byKey(TransferDetailView.undoKey), findsOneWidget);
      expect(_sent('GET', '/api/categories/'), isEmpty, reason: 'no edit form, no categories');
    });

    testWidgets('a family leg someone else made: no Undo, and why', (tester) async {
      final books = await _books(BookMode.family);
      await _pump(
          tester,
          (_) => EditTransactionScreen(
              transaction: _entry(type: TransactionType.outflow, addedBy: _byMum, transferId: 'tr1')),
          family: _Family(_overview(role: FamilyMember.roleOwner)),
          books: books);

      expect(find.text(_en.transferFromFamily), findsWidgets);
      expect(find.text(_en.addedByName('Mum')), findsOneWidget);
      expect(find.byKey(TransferDetailView.undoKey), findsNothing, reason: 'not even the owner');
      expect(find.text(_en.transferOnlyMakerUndo), findsOneWidget);
    });

    testWidgets('a personal leg is always mine: Undo removes both sides and closes', (tester) async {
      Object? result;
      await _pump(tester,
          (_) => EditTransactionScreen(transaction: _entry(type: TransactionType.outflow, transferId: 'tr1')),
          family: _Family(_overview()), books: BookModeProvider(), onResult: (r) => result = r);

      expect(find.text(_en.transferToFamily), findsWidgets);
      await _tapAndSettle(tester, find.byKey(TransferDetailView.undoKey));
      expect(find.text(_en.undoTransferConfirm), findsOneWidget);
      await _tapAndSettle(tester, find.byKey(TransferDetailView.undoConfirmKey));

      final delete = _sent('DELETE', '/api/transfers/').single;
      expect(delete.url.path, '/api/transfers/tr1');
      expect(delete.headers.containsKey('X-Book'), isFalse);
      expect(result, TransferDetailView.undoneResult);
    });

    for (final (code, status, message) in [
      ('transfer_gone', 409, _en.transferGone),
      ('transfer_insufficient', 400, _en.transferUndoInsufficient),
    ]) {
      testWidgets('Undo refused with $code: a clear message, the view stays', (tester) async {
        _respond = _server(undo: () => _refusal(status, code));
        Object? result = 'open';
        await _pump(tester,
            (_) => EditTransactionScreen(transaction: _entry(type: TransactionType.outflow, transferId: 'tr1')),
            family: _Family(_overview()), books: BookModeProvider(), onResult: (r) => result = r);

        await _tapAndSettle(tester, find.byKey(TransferDetailView.undoKey));
        await _tapAndSettle(tester, find.byKey(TransferDetailView.undoConfirmKey));
        expect(find.text(message), findsWidgets);
        expect(find.text('server says $code'), findsNothing);
        expect(result, 'open');
        expect(find.byType(TransferDetailView), findsOneWidget);
      });
    }

    test('labels: worked out from the book and the type', () {
      final out = _entry(type: TransactionType.outflow, transferId: 'x');
      final into = _entry(type: TransactionType.inflow, transferId: 'x');
      expect(transferLabel(_en, out, familyBook: false), _en.transferToFamily);
      expect(transferLabel(_en, into, familyBook: false), _en.transferFromFamily);
      expect(transferLabel(_en, into, familyBook: true), _en.transferToFamily);
      expect(transferLabel(_en, out, familyBook: true), _en.transferFromFamily);
    });
  });

  group('Transfer sheet', () {
    testWidgets('moves the money: amount, the default currency, today and the note', (tester) async {
      final completer = Completer<bool?>();
      await _pump(tester, (_) => const SizedBox(), family: _Family(_overview()), books: BookModeProvider(), open: false);
      final context = tester.element(find.text('open'));
      unawaited(showTransferSheet(context, direction: TransferDirection.toFamily).then(completer.complete));
      await tester.pumpAndSettle();

      expect(find.text(_en.moveToFamilyWallet), findsWidgets);
      await tester.enterText(find.byKey(TransferSheet.amountKey), '500');
      await tester.enterText(find.byKey(TransferSheet.noteKey), 'For groceries');
      await tester.pump();
      await _tapAndSettle(tester, find.byKey(TransferSheet.submitKey));

      final post = _sent('POST', '/api/transfers').single;
      final body = _bodyOf(post);
      expect(body['direction'], 'to_family');
      expect(body['amount'], 500);
      expect(body['currency'], 'usd');
      expect(body['description'], 'For groceries');
      final date = DateTime.parse(body['date'] as String);
      final today = DateTime.now();
      expect([date.year, date.month, date.day], [today.year, today.month, today.day]);
      expect(completer.isCompleted, isTrue);
      expect(await completer.future, isTrue);
      expect(find.byType(TransferSheet), findsNothing);
    });

    testWidgets('transfer_insufficient: shown in the sheet, which stays open', (tester) async {
      _respond = _server(transfer: () => _refusal(400, 'transfer_insufficient'));
      await openSheet(tester, TransferDirection.toPersonal);
      expect(find.text(_en.takeFromFamilyWallet), findsWidgets);
      await tester.enterText(find.byKey(TransferSheet.amountKey), '900');
      await tester.pump();
      await _tapAndSettle(tester, find.byKey(TransferSheet.submitKey));

      expect(_bodyOf(_sent('POST', '/api/transfers').single)['direction'], 'to_personal');
      expect(find.descendant(of: find.byType(TransferSheet), matching: find.text(_en.transferInsufficient)),
          findsOneWidget);
      expect(find.byType(TransferSheet), findsOneWidget);
    });

    testWidgets('MMK is whole kyat: a decimal point is not taken', (tester) async {
      await openSheet(tester, TransferDirection.toFamily);
      await _tapAndSettle(tester, find.byKey(TransferSheet.currencyKey(Currency.mmk)));
      await tester.enterText(find.byKey(TransferSheet.amountKey), '12.5');
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(TransferSheet.amountKey)).controller!.text, isNot(contains('.')));
      await tester.enterText(find.byKey(TransferSheet.amountKey), '1500');
      await tester.pump();
      await _tapAndSettle(tester, find.byKey(TransferSheet.submitKey));
      final body = _bodyOf(_sent('POST', '/api/transfers').single);
      expect(body['currency'], 'mmk');
      expect(body['amount'], 1500);
    });

    test('which transfer Home offers', () {
      expect(transferActionFor(inFamily: false, readOnly: false, mode: BookMode.personal), isNull);
      expect(transferActionFor(inFamily: true, readOnly: true, mode: BookMode.personal), isNull);
      expect(transferActionFor(inFamily: true, readOnly: false, mode: BookMode.personal), TransferDirection.toFamily);
      expect(transferActionFor(inFamily: true, readOnly: false, mode: BookMode.family), TransferDirection.toPersonal);
    });
  });

  group('Home', () {
    testWidgets('Personal mode in a family: "Move to family wallet" in the add sheet', (tester) async {
      await _pumpHome(tester, family: _Family(_overview()), books: BookModeProvider());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text(_en.moveToFamilyWallet), findsOneWidget);
      expect(find.text(_en.takeFromFamilyWallet), findsNothing);
      await _tapAndSettle(tester, find.text(_en.moveToFamilyWallet));
      expect(find.byType(TransferSheet), findsOneWidget);
    });

    testWidgets('Myanmar 360: the add sheet with the transfer option fits', (tester) async {
      await _pumpHome(tester, family: _Family(_overview()), books: BookModeProvider(), locale: const Locale('my'));
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      _expectFits(tester, find.text(_my.moveToFamilyWallet), 360);
      _expectFits(tester, find.text(_my.moveToFamilyHint), 360);
    });

    testWidgets('Family mode: "Take from family wallet"', (tester) async {
      final books = await _books(BookMode.family);
      await _pumpHome(tester, family: _Family(_overview()), books: books);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text(_en.takeFromFamilyWallet), findsOneWidget);
      expect(find.text(_en.moveToFamilyWallet), findsNothing);
    });

    testWidgets('no family, or a read-only family: no transfer option', (tester) async {
      await _pumpHome(tester, family: _Family(), books: BookModeProvider());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text(_en.manualEntry), findsOneWidget);
      expect(find.text(_en.moveToFamilyWallet), findsNothing);

      await _pumpHome(tester, family: _Family(_overview(readOnly: true)), books: BookModeProvider());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text(_en.moveToFamilyWallet), findsNothing);
    });

    testWidgets('Recent: a transfer row has the transfer icon and label, not its category', (tester) async {
      await _pumpHome(tester, family: _Family(_overview()), books: BookModeProvider());
      expect(find.text(_en.transferToFamily), findsOneWidget);
      expect(find.text('Family wallet'), findsNothing);
      expect(find.text('Transfer'), findsNothing);
      expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);
    });
  });

  group('Transactions list', () {
    test('the net total leaves transfers out', () {
      final list = [
        _entry(type: TransactionType.inflow).copyWithAmount(100),
        _entry(type: TransactionType.outflow, transferId: 'tr1'),
      ];
      expect(transactionsNetTotal(list, Currency.usd), formatMoney(100, Currency.usd, showPlus: true));
      expect(transactionsNetTotal([_entry(transferId: 'x')], Currency.mmk), formatMoney(0, Currency.mmk));
    });
  });

  group('Analytics', () {
    Future<void> pumpChart(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => _FakeAnalyticsNotifications()),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('my')],
          home: screen,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('spending totals ignore transfers', (tester) async {
      await pumpChart(tester, const OutflowAnalyticsScreen(transactionLoader: _chartLoader));
      expect(find.text('Transfer'), findsNothing);
      expect(find.text(formatMoney(100, Currency.usd)), findsWidgets);
      expect(find.text(formatMoney(600, Currency.usd)), findsNothing);
    });

    testWidgets('income totals ignore transfers', (tester) async {
      await pumpChart(tester, const InflowAnalyticsScreen(transactionLoader: _chartLoader));
      expect(find.text('Transfer'), findsNothing);
      expect(find.text(formatMoney(200, Currency.usd)), findsWidgets);
      expect(find.text(formatMoney(500, Currency.usd)), findsNothing);
    });
  });

  group('360 px, Myanmar and English, light and dark', () {
    for (final locale in const [Locale('my'), Locale('en')]) {
      for (final themeMode in const [ThemeMode.light, ThemeMode.dark]) {
        final l = locale.languageCode == 'my' ? _my : _en;
        final tag = '${locale.languageCode} ${themeMode.name}';

        testWidgets('$tag: New entry with a long family name; the crowded top bar still fits', (tester) async {
          final books = await _books(BookMode.family);
          const longName = 'ဦးအောင်သူဝင်းနှင့် ဒေါ်ခင်မြတ်တို့ ရန်ကုန်မိသားစု';
          await _pump(tester, _addScreen,
              family: _Family(_overview(name: longName)),
              books: books,
              locale: locale,
              themeMode: themeMode,
              size: const Size(360, 780));
          _expectFits(tester, find.byKey(AddTransactionScreen.bookChipKey), 360);
          _expectFits(tester, find.byKey(ForWhomPicker.rowKey), 360);
          _expectFits(tester, _inBar(find.byIcon(Icons.mic_rounded)), 360);
          _expectFits(tester, _inBar(find.text(l.save)), 360);
          final title = _inBar(find.byType(AppBarTitle));
          if (title.evaluate().isNotEmpty) {
            expect(tester.getRect(title).right,
                lessThanOrEqualTo(tester.getRect(_inBar(find.byIcon(Icons.mic_rounded))).left));
          }

          await _tapAndSettle(tester, find.byKey(ForWhomPicker.rowKey));
          _expectFits(tester, find.byKey(ForWhomPicker.wholeFamilyKey), 360);
          _expectFits(tester, find.byKey(ForWhomPicker.doneKey), 360);
        });

        testWidgets('$tag: Edit as a member, someone else\'s entry', (tester) async {
          final books = await _books(BookMode.family);
          await _pump(tester, (_) => EditTransactionScreen(transaction: _entry(addedBy: _byUncle, forWhom: ['p1', 'm3'])),
              family: _Family(_overview()), books: books, locale: locale, themeMode: themeMode, size: const Size(360, 780));
          _expectFits(tester, find.text(l.entryNotYoursReason), 360);
          _expectFits(tester, find.text(l.addedByName(l.familyFormerName('Uncle'))), 360);
          _expectFits(tester, find.byKey(ForWhomPicker.rowKey), 360);
          _expectFits(tester, _inBar(find.byType(AppBarSaveButton)), 360);
        });

        testWidgets('$tag: a transfer and its Undo', (tester) async {
          final books = await _books(BookMode.family);
          await _pump(
              tester,
              (_) => EditTransactionScreen(
                  transaction: _entry(
                      type: TransactionType.inflow,
                      addedBy: _byMe,
                      transferId: 'tr1',
                      description: 'For the electricity bill and the water bill this month')),
              family: _Family(_overview()),
              books: books,
              locale: locale,
              themeMode: themeMode,
              size: const Size(360, 780));
          _expectFits(tester, find.byKey(TransferDetailView.undoKey), 360);
          _expectFits(tester, find.text(l.transferToFamily), 360);
          await _tapAndSettle(tester, find.byKey(TransferDetailView.undoKey));
          _expectFits(tester, find.byKey(TransferDetailView.undoConfirmKey), 360);
        });

        testWidgets('$tag: the transfer sheet with its error', (tester) async {
          _respond = _server(transfer: () => _refusal(400, 'transfer_insufficient'));
          await openSheet(tester, TransferDirection.toPersonal, locale: locale, themeMode: themeMode, width: 360);
          await tester.enterText(find.byKey(TransferSheet.amountKey), '123456789');
          await tester.pump();
          await _tapAndSettle(tester, find.byKey(TransferSheet.submitKey));
          _expectFits(tester, find.text(l.transferInsufficient), 360);
          _expectFits(tester, find.byKey(TransferSheet.submitKey), 360);
          for (final c in Currency.values) {
            _expectFits(tester, find.byKey(TransferSheet.currencyKey(c)), 360);
          }
        });
      }
    }
  });
}

extension on Transaction {
  Transaction copyWithAmount(double amount) => Transaction(
        id: id,
        bookId: bookId,
        type: type,
        mainCategory: mainCategory,
        subCategory: subCategory,
        date: date,
        amount: amount,
        currency: currency,
        createdAt: createdAt,
        updatedAt: updatedAt,
        transferId: transferId,
      );
}
