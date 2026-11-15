import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/chat.dart';
import 'package:frontend/models/custom_insight.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/models/insight.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/custom_insight_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/providers/insight_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/ai/ai_chat_screen.dart';
import 'package:frontend/screens/insights/insights_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/book_chip.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what each request carried.
class _Sent {
  _Sent(this.history, this.book);
  final List<ChatMessage> history;
  final BookMode book;
}

class _Streamer {
  final List<_Sent> sent = [];
  final List<StreamController<String>> controllers = [];

  /// Each call answers with a stream the test feeds itself.
  Stream<String> call({
    required String message,
    List<ChatMessage>? chatHistory,
    ResponseStyle? responseStyle,
    ChatMode mode = ChatMode.standard,
    void Function(ChatStreamMeta meta)? onMeta,
  }) {
    sent.add(_Sent(List.of(chatHistory ?? const []), ApiService.bookMode));
    final c = StreamController<String>();
    controllers.add(c);
    return c.stream;
  }
}

class _EmptyChat extends ChatProvider {
  _EmptyChat({super.streamer});
  @override
  Future<void> loadChatHistory() async {}
}

class _FakeFamily extends FamilyProvider {
  _FakeFamily({this.name = 'Aung family', this.people = const []});
  final String name;
  final List<FamilyMember> people;

  @override
  Family? get family => Family(id: 'f1', name: name, readOnly: false);
  @override
  bool get inFamily => true;
  @override
  List<FamilyMember> get members => people;
  @override
  bool get loaded => true;
  @override
  Future<void> refresh() async {}
}

FamilyMember _member(String id, String name, {String kind = FamilyMember.kindAccount}) => FamilyMember(
      id: id,
      displayName: name,
      kind: kind,
      role: 'member',
      status: 'active',
      isMe: false,
    );

const _delegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class _NoCustom implements CustomInsightClient {
  @override
  Future<CustomInsightPage> list({String? before}) async => CustomInsightPage(reports: const [], nextBefore: null);
  @override
  Future<CustomInsight> get(String id) => throw UnimplementedError();
  @override
  Future<CustomInsightCreateResult> create(CustomInsightRequest request) => throw UnimplementedError();
  @override
  Future<CustomInsight> translate(String id) => throw UnimplementedError();
  @override
  Future<void> delete(String id) => throw UnimplementedError();
}

class _Auth extends AuthProvider {
  @override
  bool get isPro => true;
  @override
  bool get isPaid => true;
}

/// A spinner may never stop, so a few timed pumps instead of pumpAndSettle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
    ApiService.bookMode = BookMode.personal;
  });
  tearDown(() => ApiService.bookMode = BookMode.personal);

  final en = AppLocalizations(const Locale('en'));
  final my = AppLocalizations(const Locale('my'));

  // -------------------------------------------------------------------------
  group('the conversation belongs to one book', () {
    late BookModeProvider books;
    late _Streamer streamer;
    late ChatProvider chat;

    setUp(() {
      books = BookModeProvider();
      streamer = _Streamer();
      chat = ChatProvider(streamer: streamer.call);
      // What BookSession does on every switch.
      books.onModeChanged = chat.resetBook;
    });

    Future<void> answer(String question, String reply) async {
      await chat.sendMessage(question);
      final c = streamer.controllers.last;
      c.add(reply);
      await c.close();
      await Future<void>.delayed(Duration.zero);
    }

    test('Personal to Family mid-conversation: chat_history has no Personal turn, and the book is family',
        () async {
      await answer('How much did I spend on my rent?', 'You spent K500,000.');
      expect(chat.messages, hasLength(2));

      await books.setMode(BookMode.family);
      expect(chat.messages, isEmpty);

      await chat.sendMessage('How much did we spend this month?');
      final request = streamer.sent.last;
      expect(request.book, BookMode.family);
      expect(request.history, isEmpty, reason: 'nothing of the Personal talk may reach the family book');
      expect(chat.messages.map((m) => m.content), isNot(contains('How much did I spend on my rent?')));
    });

    test('Family back to Personal: the family turns stay out too', () async {
      await books.setMode(BookMode.family);
      await answer('What did we spend on the kids?', 'K90,000.');
      await books.setMode(BookMode.personal);
      await chat.sendMessage('And me?');
      expect(streamer.sent.last.book, BookMode.personal);
      expect(streamer.sent.last.history, isEmpty);
    });

    test('a stream still running when the mode switches does not write into the new conversation', () async {
      await chat.sendMessage('How much did I spend on my rent?');
      final late = streamer.controllers.last;
      late.add('You spe');

      await books.setMode(BookMode.family);
      late.add('nt K500,000 on rent.'); // arrives after the switch
      await late.close();
      await Future<void>.delayed(Duration.zero);

      expect(chat.messages, isEmpty);
      expect(chat.isStreaming, isFalse);
      expect(chat.error, isNull);

      await chat.sendMessage('How much did we spend this month?');
      expect(streamer.sent.last.history, isEmpty);
      expect(chat.messages.first.content, 'How much did we spend this month?');
    });

    test('a send waiting for the old stream to close, when the mode switches, is dropped', () async {
      final slowCancel = Completer<void>();
      final stuck = StreamController<String>(onCancel: () => slowCancel.future);
      var calls = 0;
      final slowChat = ChatProvider(
        streamer: ({required message, chatHistory, responseStyle, mode = ChatMode.standard, onMeta}) {
          calls++;
          return calls == 1 ? stuck.stream : const Stream<String>.empty();
        },
      );
      books.onModeChanged = slowChat.resetBook;

      await slowChat.sendMessage('first, in Personal');
      final second = slowChat.sendMessage('second, typed in Personal'); // waits on the cancel above
      await Future<void>.delayed(Duration.zero);

      await books.setMode(BookMode.family);
      slowCancel.complete();
      expect(await second, isFalse);
      expect(calls, 1, reason: 'the Personal question must not be sent to the family book');
      expect(slowChat.messages, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('the chat screen in Family mode', () {
    Future<void> open(
      WidgetTester tester, {
      required ChatProvider chat,
      BookModeProvider? books,
      FamilyProvider? family,
      String lang = 'en',
      double width = 390,
      ThemeMode themeMode = ThemeMode.light,
    }) async {
      tester.view.physicalSize = Size(width * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
          ChangeNotifierProvider(create: (_) => PlanProvider(loader: () async => PlanStatus(plan: Plan.free))),
          if (family != null) ChangeNotifierProvider<FamilyProvider>.value(value: family),
          if (books != null) ChangeNotifierProvider<BookModeProvider>.value(value: books),
        ],
        child: MaterialApp(
          locale: Locale(lang),
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          localizationsDelegates: _delegates,
          supportedLocales: const [Locale('en'), Locale('my')],
          home: AiChatScreen(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<BookModeProvider> familyBooks(WidgetTester tester) async {
      final books = BookModeProvider();
      await tester.runAsync(() => books.setMode(BookMode.family));
      return books;
    }

    testWidgets('subtitle, welcome and suggestions are about the family book', (tester) async {
      final books = await familyBooks(tester);
      await open(tester,
          chat: _EmptyChat(),
          books: books,
          family: _FakeFamily(people: [
            _member('m1', 'Dad'),
            _member('p1', 'Ma Ma', kind: FamilyMember.kindPlaceholder),
          ]));
      final bar = find.byType(AppBar);
      expect(find.descendant(of: bar, matching: find.textContaining(en.askAboutFamily)), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.textContaining('Aung family')), findsOneWidget);
      expect(find.text(en.familyChatGreeting), findsOneWidget);
      expect(find.text(en.aiChatDes), findsNothing);
      expect(find.text('How much did we spend this month?'), findsOneWidget);
      expect(find.text('What did we spend on Ma Ma?'), findsOneWidget);
      expect(find.text(en.suggestionCurrentBalance), findsNothing);
    });

    testWidgets('no placeholders: "on the kids"', (tester) async {
      final books = await familyBooks(tester);
      await open(tester, chat: _EmptyChat(), books: books, family: _FakeFamily(people: [_member('m1', 'Dad')]));
      expect(find.text('What did we spend on the kids?'), findsOneWidget);
    });

    testWidgets('tapping a suggestion asks the family book', (tester) async {
      final books = await familyBooks(tester);
      final streamer = _Streamer();
      await open(tester, chat: _EmptyChat(streamer: streamer.call), books: books, family: _FakeFamily());
      await tester.tap(find.text('How much did we spend this month?'));
      await tester.pump();
      expect(streamer.sent, hasLength(1));
      expect(streamer.sent.single.book, BookMode.family);
    });

    testWidgets('Personal mode is unchanged', (tester) async {
      await open(tester,
          chat: _EmptyChat(), books: BookModeProvider(), family: _FakeFamily(people: [_member('m1', 'Dad')]));
      final bar = find.byType(AppBar);
      expect(find.descendant(of: bar, matching: find.text(en.aiMoneyHelper)), findsOneWidget);
      expect(find.textContaining(en.askAboutFamily), findsNothing);
      expect(find.text(en.aiChatDes), findsOneWidget);
      expect(find.text(en.suggestionCurrentBalance), findsOneWidget);
      expect(find.text(en.familyChatGreeting), findsNothing);
    });

    testWidgets('no family providers at all: as today', (tester) async {
      await open(tester, chat: _EmptyChat());
      expect(find.text(en.suggestionCurrentBalance), findsOneWidget);
    });

    for (final lang in ['en', 'my']) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('$lang 360 ${mode.name}: a long family name and long names fit', (tester) async {
          GoogleFonts.config.allowRuntimeFetching = false;
          final books = await familyBooks(tester);
          await open(tester,
              chat: _EmptyChat(),
              books: books,
              family: _FakeFamily(
                name: lang == 'my'
                    ? 'ဦးအောင်သူဝင်းနှင့် ဒေါ်ခင်မြတ်တို့ ရန်ကုန်မိသားစု'
                    : 'The Aung Thu Win and Daw Khin Myat family of Yangon',
                people: [_member('p1', 'Daw Khin Myat Thu Zar', kind: FamilyMember.kindPlaceholder)],
              ),
              lang: lang,
              width: 360,
              themeMode: mode);
          expect(tester.takeException(), isNull);
          final l = lang == 'my' ? my : en;
          expect(find.text(l.familyChatGreeting), findsOneWidget);
          expect(find.text(l.familySuggestionSpendOn('Daw Khin Myat Thu Zar')), findsOneWidget);
        });
      }
    }
  });

  // -------------------------------------------------------------------------
  group('Insights in Family mode', () {
    Future<void> open(
      WidgetTester tester, {
      required InsightFetcher fetcher,
      required bool family,
      String lang = 'en',
      double width = 390,
      ThemeMode themeMode = ThemeMode.light,
      bool customTab = false,
    }) async {
      tester.view.physicalSize = Size(width * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const SizedBox()); // a fresh screen, not the earlier one's state
      final books = BookModeProvider();
      if (family) await tester.runAsync(() => books.setMode(BookMode.family));
      final plan = PlanProvider(
        loader: () async => PlanStatus(plan: Plan.pro, features: {
          PlanFeature.insightCustom: const FeatureAllowance(mode: 'included'),
          PlanFeature.insightTranslation: const FeatureAllowance(mode: 'included'),
          PlanFeature.insightWeekly: const FeatureAllowance(mode: 'included'),
          PlanFeature.insightMonthly: const FeatureAllowance(mode: 'included'),
        }),
      );
      await tester.runAsync(plan.refresh);
      final insights = InsightProvider(fetcher: fetcher);
      final custom = CustomInsightProvider(client: _NoCustom(), pollInterval: const Duration(hours: 1), onUsageChanged: () {});
      addTearDown(() {
        plan.dispose();
        custom.dispose();
      });
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
          ChangeNotifierProvider<PlanProvider>.value(value: plan),
          ChangeNotifierProvider<InsightProvider>.value(value: insights),
          ChangeNotifierProvider<CustomInsightProvider>.value(value: custom),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ChangeNotifierProvider<FamilyProvider>.value(value: _FakeFamily()),
          ChangeNotifierProvider<BookModeProvider>.value(value: books),
        ],
        child: MaterialApp(
          locale: Locale(lang),
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          localizationsDelegates: _delegates,
          supportedLocales: const [Locale('en'), Locale('my')],
          // The Custom tab opens through its route argument.
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            settings: RouteSettings(name: '/insights', arguments: customTab ? InsightsScreen.customTabArgument : null),
            builder: (_) => InsightsScreen(),
          ),
        ),
      ));
      await settle(tester);
    }

    Future<Insight> never({required String language, required String insightType}) => Completer<Insight>().future;

    testWidgets('Family mode: plain title, the book chip names the family', (tester) async {
      await open(tester, fetcher: never, family: true);
      expect(find.text(en.aiInsights), findsOneWidget);
      expect(find.textContaining(' · Aung family'), findsNothing);
      expect(find.descendant(of: find.byKey(BookChip.chipKey), matching: find.text('Aung family')), findsOneWidget);
    });

    testWidgets('Personal mode: plain title', (tester) async {
      await open(tester, fetcher: never, family: false);
      expect(find.text(en.aiInsights), findsOneWidget);
    });

    testWidgets('Custom tab, nothing yet: says reports are shared with the family', (tester) async {
      await open(tester, fetcher: never, family: true, customTab: true);
      expect(find.text(en.customInsightEmptyList), findsOneWidget);
      expect(find.text(en.familyCustomInsightsShared), findsOneWidget);
    });

    testWidgets('Custom tab in Personal mode: no sharing line', (tester) async {
      await open(tester, fetcher: never, family: false, customTab: true);
      expect(find.text(en.customInsightEmptyList), findsOneWidget);
      expect(find.text(en.familyCustomInsightsShared), findsNothing);
    });

    testWidgets('family_read_only with nothing stored shows the read-only reason, not a generic error',
        (tester) async {
      await open(
        tester,
        family: true,
        fetcher: ({required language, required insightType}) async => throw ApiException(
          'This family is read-only',
          statusCode: 403,
          code: 'family_read_only',
        ),
      );
      expect(find.text(en.familyReadOnlyBanner), findsOneWidget);
      expect(find.text(en.insightsGenericError), findsNothing);
    });

    testWidgets('plan_cost_cap shows the server\'s message (the owner\'s cap)', (tester) async {
      await open(
        tester,
        family: true,
        fetcher: ({required language, required insightType}) async => throw PlanLimitException(
          code: PlanLimitException.codeCostCap,
          statusCode: 429,
          message: "The family owner's AI limit for this month is used up.",
        ),
      );
      expect(find.text("The family owner's AI limit for this month is used up."), findsOneWidget);
      expect(find.text(en.planCostCapBody), findsNothing);
    });

    testWidgets('plan_cost_cap in Personal mode keeps the app\'s own wording', (tester) async {
      await open(
        tester,
        family: false,
        fetcher: ({required language, required insightType}) async => throw PlanLimitException(
          code: PlanLimitException.codeCostCap,
          statusCode: 429,
          message: 'server words',
        ),
      );
      expect(find.text(en.planCostCapBody), findsOneWidget);
    });

    for (final lang in ['en', 'my']) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('$lang 360 ${mode.name}: header, read-only reason and Custom tab fit', (tester) async {
          GoogleFonts.config.allowRuntimeFetching = false;
          final l = lang == 'my' ? my : en;
          await open(
            tester,
            family: true,
            lang: lang,
            width: 360,
            themeMode: mode,
            fetcher: ({required language, required insightType}) async =>
                throw ApiException('x', statusCode: 403, code: 'family_read_only'),
          );
          expect(tester.takeException(), isNull);
          expect(find.text(l.familyReadOnlyBanner), findsOneWidget);
          await open(tester, family: true, lang: lang, width: 360, themeMode: mode, customTab: true, fetcher: never);
          expect(tester.takeException(), isNull);
          expect(find.text(l.familyCustomInsightsShared), findsOneWidget);
        });
      }
    }
  });
}
