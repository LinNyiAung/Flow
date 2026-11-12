import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/localization_service.dart';

/// The AI helper is Ko Toe Pwar (ကိုတိုးပွား) wherever it talks to the user or
/// does something for them. "AI" stays for the technology and the rules.
void main() {
  final en = AppLocalizations(const Locale('en'));
  final my = AppLocalizations(const Locale('my'));
  const enName = 'Ko Toe Pwar';

  // The helper's strings, in both languages.
  final helper = <String, String Function(AppLocalizations)>{
    'aiAssistant': (l) => l.aiAssistant,
    'aiInsights': (l) => l.aiInsights,
    'aiReasoningLabel': (l) => l.aiReasoningLabel,
    'getAiPoweredBudgetSuggestions': (l) => l.getAiPoweredBudgetSuggestions,
    'generateAiBudget': (l) => l.generateAiBudget,
    'aiWillAnalyzeAndSuggestBudgets': (l) => l.aiWillAnalyzeAndSuggestBudgets,
    'aiOptimizedBudget': (l) => l.aiOptimizedBudget,
    'aiAnalyzesSpendingAndSuggestsAmounts': (l) => l.aiAnalyzesSpendingAndSuggestsAmounts,
    'budgetWasAutomaticallyCreatedAi': (l) => l.budgetWasAutomaticallyCreatedAi,
    'nextBudgetWillBeAiOptimized': (l) => l.nextBudgetWillBeAiOptimized,
    'aiBudgetSuggestion': (l) => l.aiBudgetSuggestion,
    'aiAnalysis': (l) => l.aiAnalysis,
    'helloAi': (l) => l.helloAi,
    'aiIsTyping': (l) => l.aiIsTyping,
    'aiIsResponding': (l) => l.aiIsResponding,
    'askAi': (l) => l.askAi,
    'aiFinancialAssistant': (l) => l.aiFinancialAssistant,
    'aiFinancialAssistantDes': (l) => l.aiFinancialAssistantDes,
    'clearChatConsequence': (l) => l.clearChatConsequence,
    'assistantAnswersFromRecords': (l) => l.assistantAnswersFromRecords,
    'weeklyInsightsReceiptScanningVoiceAiBudgets': (l) => l.weeklyInsightsReceiptScanningVoiceAiBudgets,
    'planFeature_chat': (l) => l.planFeatureName('chat'),
    'planFeature_budget_suggestion': (l) => l.planFeatureName('budget_suggestion'),
  };

  for (final entry in helper.entries) {
    test('${entry.key} names Ko Toe Pwar, not "AI"', () {
      final e = entry.value(en);
      final m = entry.value(my);
      expect(e, contains(enName));
      expect(e, isNot(matches(RegExp(r'\bAI\b'))));
      expect(m, contains(_myName));
      expect(m, isNot(contains('AI')));
    });
  }

  test('the chat bar subtitle keeps it clear he is an AI', () {
    expect(en.aiMoneyHelper, 'Your AI money helper');
    expect(my.aiMoneyHelper, contains('AI'));
    expect(my.aiMoneyHelper, isNot(en.aiMoneyHelper));
  });

  test('the greeting introduces him', () {
    expect(en.helloAi, "Mingalaba! I'm Ko Toe Pwar, your money helper.");
    expect(en.aiIsResponding, 'Ko Toe Pwar is thinking…');
  });

  test('"AI" stays in the terms, privacy policy and plan limits', () {
    for (final l in [en, my]) {
      expect(l.planCostCapTitle, contains('AI'));
      expect(l.planCostCapBody, contains('AI'));
      expect(l.termsAiFeaturesTitle, contains('AI'));
      expect(l.termsAiFeaturesBody, contains('AI'));
      expect(l.termsUserResponsibilitiesBody, contains('AI'));
      expect(l.privacyAiProcessingTitle, contains('AI'));
    }
  });

  test('a plan limit sentence still reads naturally with the new name', () {
    expect(en.planLimitReachedBody(en.planFeatureName('chat')), "You've used all of your Ko Toe Pwar chat.");
    expect(en.planLimitLockedBody(en.planFeatureName('chat')), "Ko Toe Pwar chat isn't part of your plan.");
  });
}

// Spelled out once: the name in Myanmar script.
const _myName = 'ကိုတိုးပွား';
