import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/chat.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/insight_provider.dart';
import 'package:frontend/screens/ai/ai_chat_screen.dart';
import 'package:frontend/screens/insights/insights_screen.dart';
import 'package:frontend/screens/subscription/subscription_screen.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/accounts.dart';
import '../support/harness.dart';

ChatProvider chatProvider() =>
    Provider.of<ChatProvider>(T.element(find.byType(AiChatScreen)), listen: false);
InsightProvider insightProvider() =>
    Provider.of<InsightProvider>(T.element(find.byType(InsightsScreen)), listen: false);

/// The "3 of 5 left this week" line of [feature] (a PlanFeature key), or null when it is not on screen.
String? usageText(String feature) {
  final f = find.byKey(Key('plan-usage-$feature'));
  if (f.evaluate().isEmpty) return null;
  return (f.evaluate().first.widget as Text).data;
}

/// Types [text] into the chat box, sends it and waits until the answer (or refusal) is in.
Future<void> sendChat(String text) async {
  await enter(find.byType(TextField).last, text);
  await hideKeyboard();
  await tap(find.byIcon(Icons.send_rounded).last);
  await settle(500);
  final end = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(end) && chatProvider().isStreaming) {
    await T.pump(const Duration(milliseconds: 100));
  }
  await settle(800);
}

/// Opens Insights and waits for the (fake AI) insight text to show; true when it did.
Future<bool> openInsightWithContent(String contentMarker) async {
  await drawerGo(L.aiInsights);
  await waitFor(find.byType(InsightsScreen));
  final r = await waitAny([
    find.textContaining(contentMarker),
    find.text(L.failedToLoadInsights),
    find.text(L.noInsightsAvailable),
  ], timeout: const Duration(seconds: 90));
  return r == 0;
}

/// Sends [times] Advanced chat messages as [token]'s user straight to the API (arranging state, not the UI under test).
Future<void> apiAdvancedChats(String token, int times) async {
  for (var i = 0; i < times; i++) {
    final r = await http.post(Uri.parse('$kApiBase/api/chat/stream'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'message': 'E2E advanced message $i', 'mode': 'advanced'}));
    if (r.statusCode != 200) {
      throw TestFailure('API Advanced chat #$i failed: ${r.statusCode} ${r.body}');
    }
  }
}

void insightFlows() {
  group('09 Insights', () {
    e2eTest('insights: weekly/monthly stored content, Myanmar toggle, no regenerate', (t) async {
      await login(plus);
      await drawerGo(L.aiInsights);
      await waitFor(find.byType(InsightsScreen));
      final r = await waitAny([
        find.textContaining('summary'),
        find.text(L.failedToLoadInsights),
        find.text(L.noInsightsAvailable),
      ], timeout: const Duration(seconds: 90));
      check(r == 0, 'Insights: stored weekly insight not rendered (state $r: ${visibleTexts().take(15).join(' | ')})');
      // ignore: avoid_print
      print('E2E_INFO|insight type=${insightProvider().insightType}');
      check(hasText(L.healthScoreTitle) || await scrollTo(find.text(L.healthScoreTitle), maxSwipes: 4),
          'Insights: Financial Health score card missing');
      step('monthly tab');
      await scrollTo(find.text(L.monthly), dy: 500, maxSwipes: 6);
      await tap(find.text(L.monthly).first);
      final m = await waitAny([find.textContaining('Monthly summary'), find.text(L.failedToLoadInsights)],
          timeout: const Duration(seconds: 90));
      check(m == 0, 'Insights: monthly stored content not rendered (${visibleTexts().take(12).join(' | ')})');
      step('weekly tab');
      await tap(find.text(L.weekly).first);
      await waitAny([find.textContaining('Weekly summary'), find.text(L.failedToLoadInsights)],
          timeout: const Duration(seconds: 90));
      step('toggle Myanmar');
      final toMm = find.byKey(const ValueKey('insight-lang-mm'));
      if (await waitFor(toMm, timeout: const Duration(seconds: 5), orNull: true)) {
        check(find.descendant(of: toMm, matching: find.byIcon(Icons.lock_rounded)).evaluate().isEmpty,
            'Insights: မြန်မာ is locked for a Plus user');
        check(insightProvider().currentLanguage == 'en', 'Insights: a Plus user with the app in English did not start on English');
        await tap(toMm);
        final ok = await waitFor(find.textContaining('အကျဉ်းချုပ်'), timeout: const Duration(seconds: 60), orNull: true);
        check(ok, 'Insights: Myanmar toggle did not show the Myanmar content');
        check(find.byType(SubscriptionScreen).evaluate().isEmpty, 'Insights: မြန်မာ opened the Upgrade screen for a Plus user');
        await tap(find.byKey(const ValueKey('insight-lang-en')));
        check(await waitFor(find.textContaining('summary'), timeout: const Duration(seconds: 10), orNull: true),
            'Insights: switching back to English did not show English content');
        check((await SharedPreferences.getInstance()).getString(InsightProvider.languagePrefsKey) == 'en',
            'Insights: the English / မြန်မာ choice was not remembered on the device');
      } else {
        appBug('Insights: English / မြန်မာ toggle missing');
      }
      step('no regenerate button');
      check(find.byTooltip(L.regenerate).evaluate().isEmpty, 'Insights (Plus): the regenerate button is shown');
    });

    e2eTest('insights + chat (Free): monthly insight and chat are open with allowances; weekly is locked', (t) async {
      await login(free);
      step('monthly insight is generated on demand');
      check(await openInsightWithContent('Fake answer'),
          'Insights (Free): the monthly insight did not show (${visibleTexts().take(15).join(' | ')})');
      check(insightProvider().insightType == 'monthly', 'Insights (Free): did not open on the Monthly insight');
      await settle(2000);
      check(usageText('insight_monthly') == L.planUsageLeftMonth(0, 1),
          'Insights (Free): the usage line should read "${L.planUsageLeftMonth(0, 1)}" once the month\'s insight exists, was "${usageText('insight_monthly')}"');
      check(find.byTooltip(L.regenerate).evaluate().isEmpty, 'Insights (Free): a Free user can regenerate');
      step('weekly is locked with an Upgrade path');
      await tap(find.text(L.weekly).first);
      check(await waitFor(find.text(L.whatYoullGetTitle), timeout: const Duration(seconds: 15), orNull: true),
          'Insights (Free): the Weekly tab is not locked (${visibleTexts().take(15).join(' | ')})');
      check(await scrollTo(find.text(L.tryOneMonthFree), maxSwipes: 8), 'Insights (Free): the locked weekly page has no upgrade CTA');
      await tap(find.text(L.tryOneMonthFree));
      await expectSoon(find.byType(SubscriptionScreen), 'Insights (Free): the weekly CTA did not open the Upgrade screen');
      await back();

      step('chat is open with 5 a week');
      await drawerGo(L.aiAssistant);
      await waitFor(find.byType(AiChatScreen));
      await settle(2500);
      check(find.byIcon(Icons.send_rounded).evaluate().isNotEmpty, 'AI chat (Free): no message input');
      check(find.text(L.tryOneMonthFree).evaluate().isEmpty, 'AI chat (Free): still locked behind a paywall');
      check(usageText('chat') == L.planUsageLeftWeek(5, 5),
          'AI chat (Free): the usage line should read "${L.planUsageLeftWeek(5, 5)}", was "${usageText('chat')}"');
      check(find.byKey(const Key('chat-mode-switch')).evaluate().isEmpty, 'AI chat (Free): the Standard / Advanced switch is visible');
    });

    e2eTest('free_insight_myanmar_locked: Free sees မြန်မာ locked, it opens the Upgrade screen and the insight stays English', (t) async {
      await login(free);
      check(await openInsightWithContent('Fake answer'),
          'Insights (Free): the monthly insight did not show (${visibleTexts().take(15).join(' | ')})');
      final mm = find.byKey(const ValueKey('insight-lang-mm'));
      final en = find.byKey(const ValueKey('insight-lang-en'));
      check(mm.evaluate().isNotEmpty && en.evaluate().isNotEmpty, 'Insights (Free): no English / မြန်မာ toggle');
      check(find.descendant(of: mm, matching: find.byIcon(Icons.lock_rounded)).evaluate().isNotEmpty,
          'Insights (Free): မြန်မာ shows no lock');
      check(find.descendant(of: en, matching: find.byIcon(Icons.lock_rounded)).evaluate().isEmpty, 'Insights (Free): English shows a lock');
      step('tap the locked မြန်မာ');
      await tap(mm);
      await expectSoon(find.byType(SubscriptionScreen), 'Insights (Free): tapping the locked မြန်မာ did not open the Upgrade screen');
      await back();
      await waitFor(find.byType(InsightsScreen));
      await settle(800);
      check(insightProvider().currentLanguage == 'en', 'Insights (Free): the insight left English after tapping the locked မြန်မာ');
      final shown = insightProvider().getContentForLanguage() ?? '';
      check(shown.contains('Fake answer') && !RegExp('[က-႟]').hasMatch(shown),
          'Insights (Free): the insight is not the English text: $shown');
      check(hasTextContaining('Fake answer'), 'Insights (Free): the English insight is not on screen after returning');
      step('server side: translation is locked for Free');
      final r = await apiGet(await apiToken(free), '/api/insights?language=mm&insight_type=monthly');
      check(r is Map && r['translation_locked'] == true && r['content_mm'] == null,
          'API: a Free user asking for Myanmar should get English with translation_locked, got $r');
    });

    e2eTest('insights: a Plus user starts on the app language (မြန်မာ), flips for free, and the choice is remembered', (t) async {
      await login(myanmar);
      await drawerGo(LM.aiInsights);
      await waitFor(find.byType(InsightsScreen));
      check(await waitFor(find.textContaining('အကျဉ်းချုပ်'), timeout: const Duration(seconds: 90), orNull: true),
          'Insights (Plus, app in Myanmar): did not start on the Myanmar insight (${visibleTexts().take(15).join(' | ')})');
      check(insightProvider().currentLanguage == 'mm', 'Insights (Plus, app in Myanmar): the toggle did not start on မြန်မာ');
      step('flip to English');
      await tap(find.byKey(const ValueKey('insight-lang-en')));
      check(await waitFor(find.textContaining('summary'), timeout: const Duration(seconds: 10), orNull: true),
          'Insights: English did not show the English content');
      step('remembered after leaving and coming back');
      await goHome();
      await logout(l: LM);
      await login(myanmar);
      await drawerGo(LM.aiInsights);
      await waitFor(find.byType(InsightsScreen));
      check(await waitFor(find.textContaining('summary'), timeout: const Duration(seconds: 90), orNull: true),
          'Insights: the English choice was not remembered (the app language is Myanmar): ${visibleTexts().take(15).join(' | ')}');
      check(insightProvider().currentLanguage == 'en', 'Insights: remembered language is not English after signing in again');
    });
  });
}

void chatFlows() {
  group('10 AI chat', () {
    e2eTest('chat: suggested question with failing AI → friendly error, no empty bubble; clear', (t) async {
      await login(plus);
      await drawerGo(L.aiAssistant);
      await waitFor(find.byType(AiChatScreen));
      await settle(2500);
      final p = chatProvider();
      if (p.messages.isNotEmpty) {
        step('clear existing history first');
        await tap(find.byTooltip(L.clearHistory));
        await tap(find.widgetWithText(FilledButton, L.clearHistory));
        await settle(2000);
      }
      step('tap suggestion');
      await tap(find.text(L.suggestionCurrentBalance));
      await settle(500);
      final end = DateTime.now().add(const Duration(seconds: 120));
      while (DateTime.now().isBefore(end) && chatProvider().isStreaming) {
        await t.pump(const Duration(milliseconds: 200));
      }
      await settle(1500);
      final msgs = chatProvider().messages;
      final err = chatProvider().error;
      // ignore: avoid_print
      print('E2E_INFO|chat after send: ${msgs.map((m) => '${m.role.name}:${m.content.length}').join(',')} error=$err');
      check(!msgs.any((m) => m.role == MessageRole.assistant && m.content.trim().isEmpty),
          'AI chat left an EMPTY assistant bubble after the request finished');
      final answered = msgs.any((m) => m.role == MessageRole.assistant && m.content.trim().isNotEmpty);
      check(answered || err != null, 'AI chat: neither an answer nor an error after sending');
      if (err != null) {
        check(find.textContaining(err.length > 20 ? err.substring(0, 20) : err).evaluate().isNotEmpty,
            'AI chat error not shown in the UI: $err');
        check(!err.contains('Exception') && !err.contains('Traceback') && !err.contains('{'),
            'AI chat shows a raw technical error instead of a friendly message: "$err"');
      }
      check(find.text(L.suggestionCurrentBalance).evaluate().isNotEmpty,
          'User message bubble not shown after sending a suggestion');
      step('typed message');
      await enter(find.byType(TextField).last, 'How much did I spend on food?');
      await hideKeyboard();
      await tap(find.byIcon(Icons.send_rounded).last);
      final end2 = DateTime.now().add(const Duration(seconds: 120));
      await settle(500);
      while (DateTime.now().isBefore(end2) && chatProvider().isStreaming) {
        await t.pump(const Duration(milliseconds: 200));
      }
      await settle(1000);
      check(!chatProvider().messages.any((m) => m.role == MessageRole.assistant && m.content.trim().isEmpty),
          'AI chat left an EMPTY assistant bubble after the 2nd request');
      step('clear history');
      await tap(find.byTooltip(L.clearHistory));
      await tap(find.widgetWithText(FilledButton, L.clearHistory));
      await settle(2500);
      check(chatProvider().messages.isEmpty, 'Clear history left ${chatProvider().messages.length} messages');
      check(hasText(L.suggestionCurrentBalance), 'Empty chat state (suggestions) not shown after clearing');
      step('history after reopen');
      await back();
      await drawerGo(L.aiAssistant);
      await settle(2500);
      check(chatProvider().messages.isEmpty, 'Cleared chat history came back after reopening the chat');
    });

    e2eTest('free_chat_limit_sheet: Free sends 5 messages, the 6th shows the limit sheet with Upgrade', (t) async {
      await login(freeLimit);
      await drawerGo(L.aiAssistant);
      await waitFor(find.byType(AiChatScreen));
      await settle(2500);
      check(usageText('chat') == L.planUsageLeftWeek(5, 5),
          'Free chat: before the first message the line should read "${L.planUsageLeftWeek(5, 5)}", was "${usageText('chat')}"');
      for (var i = 1; i <= 5; i++) {
        step('message $i of 5');
        await sendChat('E2E free question $i');
        check(chatProvider().error == null, 'Free chat: message $i raised an error: ${chatProvider().error}');
        check(find.byKey(const Key('plan-limit-title')).evaluate().isEmpty, 'Free chat: the limit sheet showed on message $i of 5');
      }
      final answered = chatProvider().messages.where((m) => m.role == MessageRole.assistant && m.content.trim().isNotEmpty).length;
      check(answered == 5, 'Free chat: expected 5 answers after 5 messages, got $answered');
      await settle(1500);
      check(usageText('chat') == L.planUsageLeftWeek(0, 5),
          'Free chat: after 5 messages the line should read "${L.planUsageLeftWeek(0, 5)}", was "${usageText('chat')}"');

      step('6th message → limit sheet');
      await sendChat('E2E free question 6');
      final sheet = await waitFor(find.byKey(const Key('plan-limit-title')), timeout: const Duration(seconds: 15), orNull: true);
      check(sheet, 'Free chat: the 6th message showed no limit sheet (${visibleTexts().take(20).join(' | ')})');
      if (!sheet) return;
      check(find.text(L.planLimitReachedTitle).evaluate().isNotEmpty, 'Limit sheet title is not "${L.planLimitReachedTitle}"');
      check(find.text(L.planFeatureName('chat')).evaluate().isNotEmpty, 'Limit sheet does not say which feature ran out');
      check(find.byKey(const Key('plan-limit-body')).evaluate().isNotEmpty, 'Limit sheet has no explanation / reset date');
      check(chatProvider().messages.length == 10, 'Free chat: the refused 6th question stayed in the conversation (${chatProvider().messages.length} messages)');
      check(chatProvider().error == null, 'Free chat: the limit shows an error banner as well: ${chatProvider().error}');
      step('Upgrade opens the Upgrade screen');
      await tap(find.byKey(const Key('plan-limit-upgrade')));
      await expectSoon(find.byType(SubscriptionScreen), 'Limit sheet: Upgrade did not open the Upgrade screen');
      await back();
      await waitFor(find.byType(AiChatScreen));
      await settle(800);
      check(usageText('chat') == L.planUsageLeftWeek(0, 5), 'Free chat: usage line changed after the refused message: "${usageText('chat')}"');
    });

    e2eTest('pro_advanced_switch: Pro has the Standard / Advanced switch, Plus does not; Advanced runs out into a note', (t) async {
      step('Plus: no switch');
      await login(plus);
      await drawerGo(L.aiAssistant);
      await waitFor(find.byType(AiChatScreen));
      await settle(2500);
      check(find.byKey(const Key('chat-mode-switch')).evaluate().isEmpty, 'AI chat (Plus): the Standard / Advanced switch is visible');
      check(usageText('chat') != null, 'AI chat (Plus): no usage line (${visibleTexts().take(20).join(' | ')})');
      await goHome();
      await logout();

      step('Pro: switch, Standard first');
      await login(pro);
      await drawerGo(L.aiAssistant);
      await waitFor(find.byType(AiChatScreen));
      await settle(2500);
      check(find.byKey(const Key('chat-mode-switch')).evaluate().isNotEmpty, 'AI chat (Pro): no Standard / Advanced switch');
      check(find.text(L.chatModeStandard).evaluate().isNotEmpty && find.text(L.chatModeAdvanced).evaluate().isNotEmpty,
          'AI chat (Pro): the switch does not read Standard / Advanced');
      check(chatProvider().mode == ChatMode.standard, 'AI chat (Pro): the switch did not start on Standard');
      check(usageText('chat') == L.planUsageLeftMonth(400, 400), 'AI chat (Pro, Standard): usage line was "${usageText('chat')}"');
      check(usageText('chat_advanced') == null, 'AI chat (Pro, Standard): the Advanced line shows while Standard is selected');

      step('select Advanced');
      await tap(find.byKey(const ValueKey('chat-mode-advanced')));
      await settle(500);
      check(chatProvider().mode == ChatMode.advanced, 'AI chat (Pro): tapping Advanced did not select it');
      check(usageText('chat_advanced') == L.planUsageLeftMonth(100, 100),
          'AI chat (Pro, Advanced): usage line should read "${L.planUsageLeftMonth(100, 100)}", was "${usageText('chat_advanced')}"');
      check((await SharedPreferences.getInstance()).getString(ChatProvider.modePrefsKey) == 'advanced',
          'AI chat (Pro): the Advanced choice was not remembered on the device');

      step('an Advanced message uses the Advanced allowance');
      await sendChat('How much did I spend on food?');
      check(chatProvider().error == null, 'AI chat (Pro, Advanced): error ${chatProvider().error}');
      check(await waitFor(find.text(L.planUsageLeftMonth(99, 100)), timeout: const Duration(seconds: 15), orNull: true),
          'AI chat (Pro, Advanced): the Advanced line did not drop to "${L.planUsageLeftMonth(99, 100)}" (was "${usageText('chat_advanced')}")');
      check(chatProvider().mode == ChatMode.advanced && !chatProvider().advancedUsedUp,
          'AI chat (Pro): the switch left Advanced although it was not used up');

      step('use up the rest of Advanced through the API');
      await apiAdvancedChats(await apiToken(pro), 99);

      step('the next Advanced message is answered by Standard, with a note');
      await sendChat('And on transport?');
      check(chatProvider().error == null, 'AI chat (Pro, Advanced used up): error ${chatProvider().error}');
      check(await waitFor(find.byKey(const Key('chat-advanced-note')), timeout: const Duration(seconds: 10), orNull: true),
          'AI chat (Pro): no "Advanced is used up" note (${visibleTexts().take(20).join(' | ')})');
      await settle(2000); // the plan refresh brings the reset date
      check(chatProvider().mode == ChatMode.standard, 'AI chat (Pro): the switch did not return to Standard');
      check(chatProvider().messages.where((m) => m.role == MessageRole.assistant && m.content.trim().isNotEmpty).length >= 2,
          'AI chat (Pro, Advanced used up): the message was not answered by Standard');
      final noteTexts = find
          .descendant(of: find.byKey(const Key('chat-advanced-note')), matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .join(' ');
      check(RegExp(r'[A-Z][a-z]{2} \d{1,2}, \d{4}').hasMatch(noteTexts),
          'AI chat (Pro): the note does not carry the reset date taken from the plan: "$noteTexts"');
      check(usageText('chat_advanced') == null && usageText('chat') != null,
          'AI chat (Pro): after the fall-back the Standard line should show, not the Advanced one');
      check((await SharedPreferences.getInstance()).getString(ChatProvider.modePrefsKey) == 'standard',
          'AI chat (Pro): the fall-back to Standard was not remembered');
    });
  });
}
