import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/chat.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/ai/ai_chat_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlanLimitException _limit() => PlanLimitException(
      code: PlanLimitException.codeLimitReached,
      statusCode: 429,
      message: 'You have used all your AI chat messages.',
      feature: 'chat',
      upgradeAvailable: true,
    );

/// Chat screen with a provider whose first message is answered and whose
/// second one is refused by the plan once [refuse] is completed. The answered
/// first message keeps the screen from loading history from the network.
Future<ChatProvider> _openChat(WidgetTester tester, Completer<void> refuse) async {
  var calls = 0;
  final chat = ChatProvider(
    streamer: ({required message, chatHistory, responseStyle, mode = ChatMode.standard, onMeta}) {
      calls++;
      if (calls == 1) return Stream<String>.fromIterable(['Hello there']);
      Stream<String> gated() async* {
        await refuse.future;
        throw _limit();
      }

      return gated();
    },
  );
  await chat.sendMessage('first');
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
  return chat;
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump(const Duration(milliseconds: 50));
}

TextField _field(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
  });

  testWidgets('a refused question comes back into the empty input, cursor at the end', (tester) async {
    final refuse = Completer<void>();
    await _openChat(tester, refuse);

    await _send(tester, 'how much did I spend?');
    expect(_field(tester).controller!.text, isEmpty); // sent: the field was cleared

    refuse.complete();
    await tester.pump(const Duration(milliseconds: 100));

    final controller = _field(tester).controller!;
    expect(controller.text, 'how much did I spend?');
    expect(controller.selection, const TextSelection.collapsed(offset: 21));
    expect(find.byKey(const Key('plan-limit-title')), findsOneWidget); // the sheet explains
  });

  testWidgets('text typed after sending is not overwritten by the restored question', (tester) async {
    final refuse = Completer<void>();
    await _openChat(tester, refuse);

    await _send(tester, 'how much did I spend?');
    // Something lands in the field while the refused question is still in
    // flight (the field itself is disabled while the answer streams, so this
    // sets the controller, as a paste or a dictation would).
    _field(tester).controller!.text = 'something newer';
    await tester.pump();

    refuse.complete();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_field(tester).controller!.text, 'something newer');
    expect(find.byKey(const Key('plan-limit-title')), findsOneWidget); // still explained
  });
}
