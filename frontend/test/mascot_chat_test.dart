import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/chat.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/ai/ai_chat_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/mascot.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No history on the server: the chat opens on its welcome.
class _EmptyChat extends ChatProvider {
  @override
  Future<void> loadChatHistory() async {}
}

Finder _pose(MascotPose pose) =>
    find.byWidgetPredicate((w) => w is Mascot && w.pose == pose, description: 'Mascot(${pose.name})');

Future<void> _open(WidgetTester tester, ChatProvider chat, {String lang = 'en', double width = 390}) async {
  tester.view.physicalSize = Size(width * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatProvider>.value(value: chat),
        ChangeNotifierProvider(create: (_) => PlanProvider(loader: () async => PlanStatus(plan: Plan.free))),
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
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

/// A chat with one question answered.
Future<ChatProvider> _answered(WidgetTester tester) async {
  final chat = ChatProvider(
    streamer: ({required message, chatHistory, responseStyle, mode = ChatMode.standard, onMeta}) =>
        Stream<String>.fromIterable(['You spent **K412,000** on food.']),
  );
  await chat.sendMessage('How much did I spend on food?');
  await tester.pump(const Duration(milliseconds: 50));
  return chat;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'access_token': 'tok'}));
  final en = AppLocalizations(const Locale('en'));
  final my = AppLocalizations(const Locale('my'));

  testWidgets('top bar: his face, "Ko Toe Pwar" and "Your AI money helper"', (tester) async {
    await _open(tester, _EmptyChat());
    final bar = find.byType(AppBar);
    expect(find.descendant(of: bar, matching: _pose(MascotPose.face)), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text('Ko Toe Pwar')), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text(en.aiMoneyHelper)), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.byIcon(Icons.forum_rounded)), findsNothing);
  });

  testWidgets('welcome: he waves with the greeting before the first message', (tester) async {
    await _open(tester, _EmptyChat());
    expect(_pose(MascotPose.aibuddyHappy), findsOneWidget);
    expect(find.text(en.helloAi), findsOneWidget);
    expect(find.text(en.aiChatDes), findsOneWidget);
    final pose = tester.getSize(_pose(MascotPose.aibuddyHappy));
    expect(pose.height, inInclusiveRange(110, 130));
    // His welcome is above the greeting.
    expect(tester.getBottomLeft(_pose(MascotPose.aibuddyHappy)).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text(en.helloAi)).dy));
  });

  testWidgets('his face is next to his replies only', (tester) async {
    final chat = await _answered(tester);
    await _open(tester, chat);
    final list = find.byType(ListView);
    final faces = find.descendant(of: list, matching: _pose(MascotPose.face));
    expect(faces, findsOneWidget); // one assistant reply, one user message
    final size = tester.getSize(faces);
    expect(size.width, inInclusiveRange(24, 28));
    // Beside the reply, to its left.
    final reply = find.textContaining('on food.');
    expect(tester.getTopRight(faces).dx, lessThanOrEqualTo(tester.getTopLeft(reply).dx));
    // The user's bubble has none: its row holds no Mascot.
    final userRow = find.ancestor(of: find.text('How much did I spend on food?'), matching: find.byType(Row)).first;
    expect(find.descendant(of: userRow, matching: find.byType(Mascot)), findsNothing);
  });

  for (final lang in ['en', 'my']) {
    testWidgets('$lang at 360 px: welcome and a reply fit without overflow', (tester) async {
      await _open(tester, _EmptyChat(), lang: lang, width: 360);
      expect(tester.takeException(), isNull);
      expect(find.text((lang == 'en' ? en : my).aiMoneyHelper), findsOneWidget);

      final chat = await _answered(tester);
      await _open(tester, chat, lang: lang, width: 360);
      expect(tester.takeException(), isNull);
    });
  }
}
