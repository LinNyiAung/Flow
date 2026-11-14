import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/chat.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/book_session.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ONE MockClient for the file (ApiService binds its inner client once).
late Future<http.Response> Function(http.Request) _respond;
final List<http.Request> _requests = [];
final _mock = MockClient((request) {
  _requests.add(request);
  return _respond(request);
});

Future<T> _run<T>(Future<T> Function() call) => http.runWithClient(call, () => _mock);

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _overview() => {
      'family': {'id': 'f1', 'name': 'Aung family', 'read_only': false},
      'me': {'member_id': 'm1', 'role': 'owner'},
      'members': [
        {'id': 'm1', 'display_name': 'Dad', 'kind': 'account', 'role': 'owner', 'status': 'active', 'is_me': true},
      ],
      'invites': [],
      'limits': {'max_members': 6, 'max_placeholders': 20},
    };

const _noLongerMember = 'No longer in this family';

void main() {
  late BookModeProvider books;
  late FamilyProvider family;
  late GlobalKey<NavigatorState> navigatorKey;
  late List<String> messages;
  late List<String> events;
  late BookSession session;

  setUp(() {
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
    ApiService.bookMode = BookMode.personal;
    ApiService.onNoFamily = null;
    _requests.clear();
    books = BookModeProvider();
    family = FamilyProvider();
    navigatorKey = GlobalKey<NavigatorState>();
    messages = [];
    events = [];
    session = BookSession(
      books: books,
      family: family,
      navigatorKey: navigatorKey,
      resetBookData: () => events.add('reset (can pop: ${navigatorKey.currentState?.canPop()})'),
      showMessage: messages.add,
      noLongerMemberText: () => _noLongerMember,
    )..attach();
  });
  tearDown(() {
    session.detach();
    ApiService.bookMode = BookMode.personal;
    ApiService.onNoFamily = null;
  });

  group('R18: a mode change closes the screens above Home', () {
    Future<void> pumpHomeWithPushedScreen(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(navigatorKey: navigatorKey, home: const Text('home')));
      navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('personal list')));
      await tester.pumpAndSettle();
      expect(find.text('personal list'), findsOneWidget);
    }

    testWidgets('setMode pops back to Home before the reset', (tester) async {
      await pumpHomeWithPushedScreen(tester);

      await tester.runAsync(() => books.setMode(BookMode.family));
      await tester.pumpAndSettle();

      expect(find.text('personal list'), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(events, ['reset (can pop: false)']);
    });

    testWidgets('openInBook still opens its target, and Back goes to Home', (tester) async {
      await pumpHomeWithPushedScreen(tester);
      final context = tester.element(find.text('personal list'));

      await tester.runAsync(() => openInBookWith(books, family: true, open: () {
            navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('family target')));
          }));
      await tester.pumpAndSettle();
      expect(context.mounted, isFalse);
      expect(find.text('family target'), findsOneWidget);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.text('personal list'), findsNothing);
    });

    testWidgets('a no_family fallback closes the family screen and says why', (tester) async {
      await tester.runAsync(() => books.setMode(BookMode.family));
      events.clear();
      await pumpHomeWithPushedScreen(tester);
      _respond = (_) async => _json({'family': null});

      await tester.runAsync(() => _run(() async {
            ApiService.onNoFamily!();
            ApiService.onNoFamily!(); // a second failing request: no second snackbar
            await pumpEventQueue();
          }));
      await tester.pumpAndSettle();

      expect(books.mode, BookMode.personal);
      expect(find.text('personal list'), findsNothing);
      expect(events, ['reset (can pop: false)']);
      expect(messages, [_noLongerMember]);
    });
  });

  group('R19: the mode is per user and Family waits for the family', () {
    test('A (Family) logs out, B (no family) logs in: Personal, no X-Book, no snackbar; A comes back to Family',
        () async {
      SharedPreferences.setMockInitialValues({'access_token': 'tok', BookModeProvider.prefsKeyFor('a'): 'family'});
      var user = 'a';
      Completer<http.Response>? familyGate;
      _respond = (r) async {
        if (r.url.path == '/api/family') {
          if (familyGate != null) return familyGate!.future;
          return _json(user == 'a' ? _overview() : {'family': null});
        }
        return _json([]);
      };
      Future<String?> xBookOfNextRequest() async {
        _requests.clear();
        await _run(() => ApiService.getTransactions());
        return _requests.single.headers['X-Book'];
      }

      await _run(() async {
        // A signs in; until the family answers, A stays Personal.
        familyGate = Completer();
        session.signedIn('a');
        await pumpEventQueue();
        expect(books.mode, BookMode.personal);
        familyGate!.complete(_json(_overview()));
        familyGate = null;
        await pumpEventQueue();
        expect(books.mode, BookMode.family);
        expect(await xBookOfNextRequest(), 'family');

        // A logs out, B signs in.
        session.reset();
        user = 'b';
        session.signedIn('b');
        await pumpEventQueue();
        expect(books.mode, BookMode.personal);
        expect(await xBookOfNextRequest(), isNull);
        expect(messages, isEmpty);
        expect(family.inFamily, isFalse);

        // B logs out, A signs in again: back to Family once confirmed.
        session.reset();
        user = 'a';
        session.signedIn('a');
        await pumpEventQueue();
        expect(books.mode, BookMode.family);
        expect(await xBookOfNextRequest(), 'family');
        expect(messages, isEmpty);
      });
    });

    test('the family request fails: stays Personal', () async {
      SharedPreferences.setMockInitialValues({'access_token': 'tok', BookModeProvider.prefsKeyFor('a'): 'family'});
      _respond = (_) async => http.Response('<html>Bad gateway</html>', 502);
      await _run(() async {
        session.signedIn('a');
        await pumpEventQueue();
      });
      expect(books.mode, BookMode.personal);
      expect(ApiService.bookMode, BookMode.personal);
    });
  });

  group('chat settings survive a book switch', () {
    test('a Pro user switches books and Advanced is still available', () async {
      final chat = ChatProvider();
      chat.setAdvancedAvailable(true);
      await chat.setMode(ChatMode.advanced);
      final s = BookSession(
        books: BookModeProvider(),
        family: FamilyProvider(),
        navigatorKey: GlobalKey<NavigatorState>(),
        resetBookData: chat.resetBook,
        showMessage: (_) {},
        noLongerMemberText: () => '',
      )..attach();

      await s.books.setMode(BookMode.family);

      expect(chat.advancedAvailable, isTrue);
      expect(chat.mode, ChatMode.advanced);
      expect(chat.messages, isEmpty);
      s.detach();

      chat.reset(); // logout still clears them
      expect(chat.advancedAvailable, isFalse);
      expect(chat.mode, ChatMode.standard);
    });
  });
}
