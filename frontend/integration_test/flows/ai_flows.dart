import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/chat.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/insight_provider.dart';
import 'package:frontend/screens/ai/ai_chat_screen.dart';
import 'package:frontend/screens/insights/insights_screen.dart';
import 'package:provider/provider.dart';

import '../support/accounts.dart';
import '../support/harness.dart';

ChatProvider chatProvider() =>
    Provider.of<ChatProvider>(T.element(find.byType(AiChatScreen)), listen: false);
InsightProvider insightProvider() =>
    Provider.of<InsightProvider>(T.element(find.byType(InsightsScreen)), listen: false);

void insightFlows() {
  group('09 Insights', () {
    e2eTest('insights: weekly/monthly stored content, Myanmar toggle, regenerate', (t) async {
      await login(premium);
      await drawerGo(L.aiInsights);
      await waitFor(find.byType(InsightsScreen));
      final r = await waitAny([
        find.textContaining('summary'),
        find.text(L.failedToLoadInsights),
        find.text(L.noInsightsAvailable),
      ], timeout: const Duration(seconds: 90));
      check(r == 0, 'Insights: stored weekly insight not rendered (state $r: ${visibleTexts().take(15).join(' | ')})');
      // ignore: avoid_print
      print('E2E_INFO|insight provider=${insightProvider().aiProvider} type=${insightProvider().insightType}');
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
      final toMm = find.text('မြန်မာ');
      if (await waitFor(toMm, timeout: const Duration(seconds: 5), orNull: true)) {
        await tap(toMm.first);
        final ok = await waitFor(find.textContaining('အကျဉ်းချုပ်'), timeout: const Duration(seconds: 60), orNull: true);
        check(ok, 'Insights: Myanmar toggle did not show the Myanmar content');
        await tap(find.text('ENGLISH').first);
        check(await waitFor(find.textContaining('summary'), timeout: const Duration(seconds: 10), orNull: true),
            'Insights: switching back to English did not show English content');
      } else {
        appBug('Insights: Myanmar translate chip missing');
      }
      step('regenerate (default provider)');
      await tap(find.byTooltip(L.regenerate), settleMs: 100);
      final sawDialog = await waitFor(find.text(L.generatingInsights), timeout: const Duration(seconds: 5), orNull: true);
      // ignore: avoid_print
      print('E2E_INFO|regenerate progress dialog shown=$sawDialog');
      await waitGone(find.text(L.generatingInsights), timeout: const Duration(seconds: 200));
      final outcome = await waitAny([find.text(L.insightsRegeneratedSuccessfully), find.byType(SnackBar)],
          timeout: const Duration(seconds: 6));
      final snack = outcome < 0
          ? '(no snackbar)'
          : find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)).evaluate()
              .map((e) => (e.widget as Text).data).join(' | ');
      final ip = insightProvider();
      // ignore: avoid_print
      print('E2E_INFO|after regenerate: loading=${ip.isLoading} actionError=${ip.actionError} error=${ip.error}');
      check(outcome >= 0, 'Insights regenerate (backend failed: ${ip.actionError}) finished without any success or error feedback (no snackbar)');
      // ignore: avoid_print
      print('E2E_INFO|regenerate outcome: $snack');
      check(find.textContaining('summary').evaluate().isNotEmpty || hasText(L.insightsRegeneratedSuccessfully),
          'Insights: content disappeared after a regenerate (snackbar: $snack)');
      check(!snack.contains('Exception'), 'Insights regenerate error shows raw exception text: $snack');
    });

    e2eTest('insights + chat: free user sees premium gate', (t) async {
      await login(free);
      await drawerGo(L.aiInsights);
      await waitFor(find.text(L.whatYoullGetTitle), timeout: const Duration(seconds: 15), orNull: true);
      check(await scrollTo(find.text(L.tryOneMonthFree), maxSwipes: 8), 'Insights (free user): no premium gate / trial CTA');
      await drawerGo(L.aiAssistant);
      await settle(1500);
      check(await scrollTo(find.text(L.tryOneMonthFree), maxSwipes: 8), 'AI chat (free user): no premium gate / trial CTA');
      check(find.byIcon(Icons.send_rounded).evaluate().isEmpty, 'AI chat (free user): message input available behind the paywall');
    });
  });
}

void chatFlows() {
  group('10 AI chat', () {
    e2eTest('chat: suggested question with failing Gemini → friendly error, no empty bubble; clear', (t) async {
      await login(premium);
      await drawerGo(L.aiAssistant);
      await waitFor(find.byType(AiChatScreen));
      await settle(2500);
      final p = chatProvider();
      // ignore: avoid_print
      print('E2E_INFO|chat provider=${p.aiProvider}');
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
  });
}
