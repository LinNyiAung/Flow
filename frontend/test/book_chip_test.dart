import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app_navigator.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/book_chip.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeFamily extends FamilyProvider {
  _FakeFamily({this.member = true, this.name = 'Aung family', this.readOnlyFlag = false});

  bool member;
  final String name;
  final bool readOnlyFlag;

  void dropOut() {
    member = false;
    notifyListeners();
  }

  @override
  Family? get family => member ? Family(id: 'f1', name: name, readOnly: readOnlyFlag) : null;
  @override
  bool get inFamily => member;
  @override
  bool get readOnly => member && readOnlyFlag;
  @override
  bool get loaded => true;
  @override
  Future<void> refresh() async {}
}

/// Counts the switches the chip asks for.
class _CountingBooks extends BookModeProvider {
  int setModeCalls = 0;

  @override
  Future<void> setMode(BookMode mode) {
    setModeCalls++;
    return super.setMode(mode);
  }
}

/// Every named route pushed, in order.
class _Pushes extends NavigatorObserver {
  final List<String?> names = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => names.add(route.settings.name);
}

final en = AppLocalizations(const Locale('en'));

Widget _budgetsPage({double? chipMaxWidth}) => Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [BookChip(routeName: '/budgets', maxWidth: chipMaxWidth)],
      ),
      body: const SizedBox(),
    );

/// The app with Home under Budgets. A mode change pops to Home first, as the
/// app root's BookSession does.
Future<_Pushes> _pump(
  WidgetTester tester, {
  required FamilyProvider? family,
  required BookModeProvider books,
  double width = 390,
  double? chipMaxWidth,
}) async {
  tester.view.physicalSize = Size(width * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  books.onModeChanged = () => navigatorKey.currentState?.popUntil((route) => route.isFirst);
  final pushes = _Pushes();
  final app = MaterialApp(
    navigatorKey: navigatorKey,
    navigatorObservers: [pushes],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('my')],
    initialRoute: '/budgets',
    routes: {
      '/': (_) => const Scaffold(body: Text('home')),
      '/budgets': (_) => _budgetsPage(chipMaxWidth: chipMaxWidth),
    },
  );
  await tester.pumpWidget(family == null
      ? app
      : MultiProvider(
          providers: [
            ChangeNotifierProvider<FamilyProvider>.value(value: family),
            ChangeNotifierProvider<BookModeProvider>.value(value: books),
          ],
          child: app,
        ));
  await tester.pumpAndSettle();
  return pushes;
}

Finder _inChip(Finder matching) => find.descendant(of: find.byKey(BookChip.chipKey), matching: matching);

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(BookChip.chipKey));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('personal: the chip says Personal with the person icon and ▾', (tester) async {
    await _pump(tester, family: _FakeFamily(), books: BookModeProvider());
    expect(_inChip(find.text('Personal')), findsOneWidget);
    expect(_inChip(find.byIcon(Icons.person_rounded)), findsOneWidget);
    expect(_inChip(find.byIcon(Icons.expand_more_rounded)), findsOneWidget);
  });

  testWidgets('family: the chip says the family name', (tester) async {
    final books = BookModeProvider();
    await books.setMode(BookMode.family);
    await _pump(tester, family: _FakeFamily(), books: books);
    expect(_inChip(find.text('Aung family')), findsOneWidget);
    expect(_inChip(find.byIcon(Icons.family_restroom_rounded)), findsOneWidget);
  });

  testWidgets('no family: no chip', (tester) async {
    await _pump(tester, family: _FakeFamily(member: false), books: BookModeProvider());
    expect(find.byKey(BookChip.chipKey), findsNothing);
    await _pump(tester, family: null, books: BookModeProvider());
    expect(find.byKey(BookChip.chipKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet lists both books with a tick on the open one', (tester) async {
    await _pump(tester, family: _FakeFamily(), books: BookModeProvider());
    await _openSheet(tester);
    expect(find.text('Which book?'), findsOneWidget);
    expect(find.byKey(const ValueKey('book-sheet-personal')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('book-sheet-family')), matching: find.text('Aung family')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('book-sheet-personal')), matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('book-sheet-family')), matching: find.byIcon(Icons.check_rounded)),
        findsNothing);
  });

  testWidgets('picking the other book switches and reopens the same screen', (tester) async {
    final books = BookModeProvider();
    final pushes = await _pump(tester, family: _FakeFamily(), books: books);
    await _openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('book-sheet-family')));
    await tester.pumpAndSettle();

    expect(books.mode, BookMode.family);
    expect(find.text('Which book?'), findsNothing);
    expect(pushes.names.last, '/budgets');
    expect(find.text('Budgets'), findsOneWidget);
    expect(_inChip(find.text('Aung family')), findsOneWidget);
    // Home, then this book's Budgets: nothing of the other book's screen left.
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isFalse);
  });

  testWidgets('picking the open book only closes the sheet', (tester) async {
    final books = _CountingBooks();
    final pushes = await _pump(tester, family: _FakeFamily(), books: books);
    final before = pushes.names.length;
    await _openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('book-sheet-personal')));
    await tester.pumpAndSettle();

    expect(books.mode, BookMode.personal);
    expect(books.setModeCalls, 0);
    expect(find.text('Which book?'), findsNothing);
    expect(pushes.names.skip(before).where((n) => n == '/budgets'), isEmpty);
    expect(find.text('Budgets'), findsOneWidget);
  });

  testWidgets('one tap, one switch', (tester) async {
    final books = _CountingBooks();
    final pushes = await _pump(tester, family: _FakeFamily(), books: books);
    final before = pushes.names.length;
    await _openSheet(tester);
    final family = find.byKey(const ValueKey('book-sheet-family'));
    await tester.tap(family);
    await tester.pump();
    if (family.evaluate().isNotEmpty) await tester.tap(family, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(books.setModeCalls, 1);
    expect(pushes.names.skip(before).where((n) => n == '/budgets').length, 1);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(navigatorKey.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two taps on the chip in the same frame open one sheet', (tester) async {
    await _pump(tester, family: _FakeFamily(), books: BookModeProvider());
    final chip = tester.widget<InkWell>(find.descendant(of: find.byKey(BookChip.chipKey), matching: find.byType(InkWell)));
    chip.onTap!(); // both before the first sheet's route is built
    chip.onTap!();
    await tester.pumpAndSettle();
    expect(find.text('Which book?'), findsOneWidget);

    navigatorKey.currentState!.pop(); // closing it leaves Budgets, not a second sheet
    await tester.pumpAndSettle();
    expect(find.text('Which book?'), findsNothing);
    expect(find.text('Budgets'), findsOneWidget);

    await _openSheet(tester); // and the chip opens it again afterwards
    expect(find.text('Which book?'), findsOneWidget);
  });

  testWidgets('two taps on a book in the same frame switch once', (tester) async {
    final books = _CountingBooks();
    final pushes = await _pump(tester, family: _FakeFamily(), books: books);
    final before = pushes.names.length;
    await _openSheet(tester);
    final row = tester.widget<ListTile>(find.byKey(const ValueKey('book-sheet-family')));
    row.onTap!();
    row.onTap!();
    await tester.pumpAndSettle();

    expect(books.setModeCalls, 1);
    expect(pushes.names.skip(before).where((n) => n == '/budgets').length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the open sheet closes when the family goes away', (tester) async {
    final family = _FakeFamily();
    final books = _CountingBooks();
    await _pump(tester, family: family, books: books);
    await _openSheet(tester);
    expect(find.byKey(const ValueKey('book-sheet-family')), findsOneWidget);

    family.dropOut(); // removed, left or deleted while the sheet is open
    await tester.pumpAndSettle();

    expect(find.text('Which book?'), findsNothing);
    expect(find.text('Budgets'), findsOneWidget);
    expect(books.setModeCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chip goes away with the family', (tester) async {
    final family = _FakeFamily();
    await _pump(tester, family: family, books: BookModeProvider());
    expect(find.byKey(BookChip.chipKey), findsOneWidget);
    family.dropOut();
    await tester.pumpAndSettle();
    expect(find.byKey(BookChip.chipKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only shows a lock and still switches', (tester) async {
    final books = BookModeProvider();
    await books.setMode(BookMode.family);
    await _pump(tester, family: _FakeFamily(readOnlyFlag: true), books: books);
    expect(_inChip(find.byIcon(Icons.lock_rounded)), findsOneWidget);
    expect(_inChip(find.byIcon(Icons.expand_more_rounded)), findsNothing);

    await _openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('book-sheet-personal')));
    await tester.pumpAndSettle();
    expect(books.mode, BookMode.personal);
    expect(_inChip(find.text('Personal')), findsOneWidget);
  });

  testWidgets('semantics label names the book', (tester) async {
    final books = BookModeProvider();
    await books.setMode(BookMode.family);
    await _pump(tester, family: _FakeFamily(), books: books);
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel(en.bookChipLabel('Aung family')), findsOneWidget);
    // A screen reader's double-tap opens the sheet.
    final node = tester.getSemantics(find.byKey(BookChip.chipKey));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(find.text('Which book?'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('no room for the name: the chip keeps its icon and ▾, the label stays', (tester) async {
    final books = BookModeProvider();
    await books.setMode(BookMode.family);
    await _pump(tester, family: _FakeFamily(), books: books, chipMaxWidth: 70);
    expect(_inChip(find.byIcon(Icons.family_restroom_rounded)), findsOneWidget);
    expect(_inChip(find.byIcon(Icons.expand_more_rounded)), findsOneWidget);
    expect(_inChip(find.text('Aung family')), findsNothing);
    expect(tester.getSize(find.byKey(BookChip.chipKey)).width, lessThanOrEqualTo(70));
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel(en.bookChipLabel('Aung family')), findsOneWidget);
    handle.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long name is cut at 40% width', (tester) async {
    final books = BookModeProvider();
    await books.setMode(BookMode.family);
    final name = 'The Aung Thu Win and Daw Khin Myat family of Yangon, Bahan';
    await _pump(tester, family: _FakeFamily(name: name), books: books, width: 360);
    expect(tester.getSize(find.byKey(BookChip.chipKey)).width, lessThanOrEqualTo(360 * 0.4));
    final label = tester.widget<Text>(_inChip(find.text(name)));
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  test('strings exist in en and my', () {
    final my = AppLocalizations(const Locale('my'));
    expect(en.bookSheetTitle, 'Which book?');
    expect(my.bookSheetTitle, 'ဘယ်စာရင်းကို ကြည့်မလဲ');
    expect(en.bookChipLabel('x'), 'Book: x. Tap to switch');
    expect(my.bookChipLabel('x'), 'စာရင်း - x။ ပြောင်းရန် နှိပ်ပါ');
  });
}
