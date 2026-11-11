import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/chat.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/ai/ai_chat_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _reply = '## Fake answer\nYou spent **a lot** on groceries.\n\n- Rice\n- Cooking oil';

/// Every text shown on screen, rich text included.
List<String> _visibleTexts(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? t.textSpan?.toPlainText() ?? '',
      for (final t in tester.widgetList<RichText>(find.byType(RichText))) t.text.toPlainText(),
    ];

/// Chat screen whose first question ([firstQuestion]) was answered with
/// [firstReply]; later questions are answered by [later] (if given). The
/// answered first message keeps the screen from loading history from the network.
Future<void> _openChat(
  WidgetTester tester, {
  String firstQuestion = 'how much on food?',
  String firstReply = _reply,
  Stream<String> Function()? later,
}) async {
  var calls = 0;
  final chat = ChatProvider(
    streamer: ({required message, chatHistory, responseStyle, mode = ChatMode.standard, onMeta}) {
      calls++;
      if (calls == 1 || later == null) return Stream<String>.fromIterable([firstReply]);
      return later();
    },
  );
  await chat.sendMessage(firstQuestion);
  await tester.pump(const Duration(milliseconds: 50));

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatProvider>.value(value: chat),
        ChangeNotifierProvider(create: (_) => PlanProvider(loader: () async => PlanStatus(plan: Plan.free))),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('my')],
        home: AiChatScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'access_token': 'tok'}));

  testWidgets('an assistant reply renders headings, bold and lists without the symbols', (tester) async {
    await _openChat(tester);

    expect(find.byType(MarkdownBody), findsOneWidget);
    final texts = _visibleTexts(tester);
    expect(texts, contains('Fake answer'));
    expect(texts.any((t) => t.contains('You spent a lot on groceries.')), isTrue, reason: '$texts');
    expect(texts, contains('Rice'));
    expect(texts, contains('Cooking oil'));
    for (final t in texts) {
      expect(t, isNot(contains('**')));
      expect(t, isNot(contains('##')));
      expect(t, isNot(startsWith('- ')));
    }
    // "a lot" is drawn bold.
    final bold = tester
        .widgetList<RichText>(find.byType(RichText))
        .expand((r) {
          final spans = <TextSpan>[];
          r.text.visitChildren((s) {
            if (s is TextSpan && s.text == 'a lot') spans.add(s);
            return true;
          });
          return spans;
        })
        .toList();
    expect(bold, isNotEmpty);
    expect(bold.first.style?.fontWeight, FontWeight.w800);
  });

  testWidgets("a user's message with ** stays literal", (tester) async {
    await _openChat(tester, firstQuestion: 'is **this** bold?', firstReply: 'No.');

    expect(find.text('is **this** bold?'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget); // only the assistant's "No."
  });

  testWidgets('a reply with a table falls back to plain text', (tester) async {
    await _openChat(tester, firstReply: '| Item | Spent |\n|---|---|\n| Rice | 10 |');

    expect(find.byType(MarkdownBody), findsNothing);
    final texts = _visibleTexts(tester);
    expect(texts.any((t) => t.contains('Rice') && !t.contains('|')), isTrue, reason: '$texts');
  });

  testWidgets('streaming: busy dots first, then partial Markdown, then the whole reply', (tester) async {
    final controller = StreamController<String>();
    await _openChat(tester, firstReply: 'Hi.', later: () => controller.stream);

    await tester.enterText(find.byType(TextField), 'list my top spending');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('chat-busy-dots')), findsOneWidget);

    controller.add('- Groceries **12');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('chat-busy-dots')), findsNothing);
    expect(_visibleTexts(tester).any((t) => t.contains('Groceries')), isTrue);

    controller.add('0 USD**\n- Transport');
    await controller.close();
    await tester.pump(const Duration(milliseconds: 100));
    final texts = _visibleTexts(tester);
    expect(texts.any((t) => t.contains('Groceries 120 USD')), isTrue, reason: '$texts');
    expect(texts, contains('Transport'));
    expect(texts.where((t) => t.contains('**')), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
