import 'package:flutter/material.dart';

import 'package:frontend/models/custom_insight.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/custom_insight_ranges.dart';

// Text and small dialogs shared by the custom insight tab, form and report
// screen.

/// The label of a [CustomInsightPreset] key.
String customPresetLabel(AppLocalizations l, String key) {
  switch (key) {
    case CustomInsightPreset.whereToSave:
      return l.customPresetWhereToSave;
    case CustomInsightPreset.comparePrevious:
      return l.customPresetComparePrevious;
    case CustomInsightPreset.biggestChanges:
      return l.customPresetBiggestChanges;
    case CustomInsightPreset.budgetsGoals:
      return l.customPresetBudgetsGoals;
    default:
      return key;
  }
}

/// What the report was asked: the preset's label, the user's own question, or
/// "Full insight" when neither was given.
String customInsightTitle(AppLocalizations l, CustomInsight report) {
  final preset = report.preset;
  if (preset != null) return customPresetLabel(l, preset);
  final text = report.instruction?.trim() ?? '';
  return text.isEmpty ? l.customInsightFullInsight : text;
}

/// "1 October 2026 – 31 October 2026".
String customRangeText(AppLocalizations l, DateTime start, DateTime end) =>
    '${l.formatPlanDate(start)} – ${l.formatPlanDate(end)}';

String customRangeProblemText(AppLocalizations l, CustomRangeProblem problem) {
  switch (problem) {
    case CustomRangeProblem.endBeforeStart:
      return l.customRangeEndBeforeStart;
    case CustomRangeProblem.tooShort:
      return l.customRangeTooShort;
    case CustomRangeProblem.tooLong:
      return l.customRangeTooLong;
    case CustomRangeProblem.inFuture:
      return l.customRangeInFuture;
  }
}

/// The text for a failed custom insight call: the app's own sentence for the
/// codes it knows, otherwise the server's [fallback] message.
String customErrorText(AppLocalizations l, String? code, String fallback) {
  switch (code) {
    case CustomInsightRequestException.pending:
      return l.customErrorPending;
    case CustomInsightRequestException.attempts:
      return l.customErrorAttempts;
    case CustomInsightRequestException.noData:
      return l.customErrorNoData;
    default:
      return fallback.trim().isEmpty ? l.genericErrorOccurred : fallback;
  }
}

/// Asks "Delete this custom insight?". True only when the user confirmed.
Future<bool> confirmDeleteCustomInsight(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Text(l.customInsightDeleteConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l.dialogCancel),
        ),
        TextButton(
          key: const Key('custom-insight-delete-confirm'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l.customInsightDelete),
        ),
      ],
    ),
  );
  return confirmed == true;
}
