import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:frontend/models/custom_insight.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/providers/custom_insight_provider.dart';
import 'package:frontend/screens/insights/custom_insight_report_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/custom_insight_ranges.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/plan_limit_sheet.dart';
import 'package:frontend/widgets/plan_usage_line.dart';

// ── Text shared by the custom insight screens ───────────────────────────

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

/// Opens a report.
Future<void> openCustomInsightReport(BuildContext context, String reportId) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => CustomInsightReportScreen(reportId: reportId)),
  );
}

// ── The create form ─────────────────────────────────────────────────────

/// Today's date (date-only) in the app timezone the server checks ranges in:
/// Asia/Yangon, UTC+06:30 with no daylight saving. The device's own date can
/// be a day behind or ahead of it, and the server refuses a range that ends
/// after its today.
DateTime customInsightToday([DateTime? nowUtc]) {
  final yangon = (nowUtc ?? DateTime.now().toUtc()).add(const Duration(hours: 6, minutes: 30));
  return DateTime(yangon.year, yangon.month, yangon.day);
}

/// Opens the "New custom insight" sheet. A created report is announced with a
/// snackbar; a reused one (the user already has it) is opened. [today] is for
/// tests; it defaults to today in the app timezone ([customInsightToday]).
Future<void> showCustomInsightForm(BuildContext context, {DateTime? today}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = AppLocalizations.of(context);
  final day = today ?? customInsightToday();

  final result = await showAppBottomSheet<CustomInsightCreateResult>(
    context: context,
    builder: (_) => _CustomInsightForm(today: day),
  );
  if (result == null || !context.mounted) return;

  if (!result.reused && result.report.isPending) {
    messenger.showSnackBar(SnackBar(content: Text(l.customInsightCreating)));
    return;
  }
  if (result.reused) {
    messenger.showSnackBar(SnackBar(content: Text(l.customInsightReused)));
  }
  await openCustomInsightReport(context, result.report.id);
}

/// Allows at most [max] characters counted the way the server counts them
/// (code points), so a long Myanmar text is not cut earlier or let through.
class _CodePointLimit extends TextInputFormatter {
  _CodePointLimit(this.max);
  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.runes.length <= max) return newValue;
    final cut = String.fromCharCodes(newValue.text.runes.take(max));
    return TextEditingValue(text: cut, selection: TextSelection.collapsed(offset: cut.length));
  }
}

class _CustomInsightForm extends StatefulWidget {
  const _CustomInsightForm({required this.today});

  final DateTime today;

  @override
  State<_CustomInsightForm> createState() => _CustomInsightFormState();
}

class _CustomInsightFormState extends State<_CustomInsightForm> {
  final TextEditingController _instruction = TextEditingController();
  late DateRangeChoice _range = quickRange(CustomQuickRange.last30Days, widget.today);

  /// The quick range chosen; null when the dates were picked by hand.
  CustomQuickRange? _quick = CustomQuickRange.last30Days;
  String? _preset;
  bool _submitting = false;
  String? _error;

  DateTime get _today => widget.today;

  @override
  void dispose() {
    _instruction.dispose();
    super.dispose();
  }

  CustomRangeProblem? get _problem => customRangeProblem(_range.start, _range.end, _today);

  void _chooseQuick(CustomQuickRange quick) {
    setState(() {
      _quick = quick;
      _range = quickRange(quick, _today);
      _error = null;
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(_today.year - 3, 1, 1),
      lastDate: _today,
      initialDateRange: DateTimeRange(start: _range.start, end: _range.end),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _quick = null;
      _range = DateRangeChoice(
        DateTime(picked.start.year, picked.start.month, picked.start.day),
        DateTime(picked.end.year, picked.end.month, picked.end.day),
      );
      _error = null;
    });
  }

  void _togglePreset(String preset) {
    setState(() {
      _preset = _preset == preset ? null : preset;
      if (_preset != null) _instruction.clear();
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting || _problem != null) return;
    final provider = context.read<CustomInsightProvider>();
    final text = _instruction.text.trim();
    final request = CustomInsightRequest(
      startDate: _range.start,
      endDate: _range.end,
      preset: _preset,
      // The server takes a preset or a question, never both.
      instruction: _preset == null && text.isNotEmpty ? text : null,
    );
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await provider.create(request);
    if (!mounted) return;
    if (result != null) {
      Navigator.pop(context, result);
      return;
    }
    final limit = provider.lastPlanLimit;
    final l = AppLocalizations.of(context);
    setState(() {
      _submitting = false;
      _error = limit == null
          ? customErrorText(l, provider.lastErrorCode, provider.lastError ?? '')
          : null;
    });
    if (limit != null) await showPlanLimitSheet(context, limit);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final problem = _problem;

    Widget rangeChip(String key, String label, CustomQuickRange quick) {
      final choice = quickRange(quick, _today);
      final usable = customRangeProblem(choice.start, choice.end, _today) == null;
      return ChoiceChip(
        key: Key('custom-range-$key'),
        label: Text(label),
        selected: _quick == quick,
        onSelected: usable && !_submitting ? (_) => _chooseQuick(quick) : null,
      );
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.customInsightNew, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              rangeChip('last30Days', l.customRangeLast30Days, CustomQuickRange.last30Days),
              rangeChip('last3Months', l.customRangeLast3Months, CustomQuickRange.last3Months),
              rangeChip('thisYear', l.customRangeThisYear, CustomQuickRange.thisYear),
              ChoiceChip(
                key: const Key('custom-range-pick'),
                avatar: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(l.customRangePick),
                selected: _quick == null,
                onSelected: _submitting ? null : (_) => _pickRange(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            customRangeText(l, _range.start, _range.end),
            key: const Key('custom-range-summary'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                customRangeProblemText(l, problem),
                key: const Key('custom-range-problem'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.error),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('custom-instruction-field'),
            controller: _instruction,
            enabled: !_submitting,
            minLines: 2,
            maxLines: 4,
            maxLength: customInstructionMaxLength,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            inputFormatters: [_CodePointLimit(customInstructionMaxLength)],
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => Text(
              '${_instruction.text.runes.length}/$customInstructionMaxLength',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            decoration: InputDecoration(
              labelText: l.customInstructionLabel,
              hintText: l.customInstructionHint,
              alignLabelWithHint: true,
            ),
            onChanged: (value) {
              // Typing replaces the ready-made question.
              if (value.isNotEmpty && _preset != null) setState(() => _preset = null);
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final preset in CustomInsightPreset.all)
                ChoiceChip(
                  key: Key('custom-preset-$preset'),
                  label: Text(customPresetLabel(l, preset)),
                  selected: _preset == preset,
                  onSelected: _submitting ? null : (_) => _togglePreset(preset),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const PlanUsageLine(feature: PlanFeature.insightCustom, padding: EdgeInsets.only(bottom: 4)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                key: const Key('custom-insight-error'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.error),
              ),
            ),
          FilledButton(
            key: const Key('custom-insight-create'),
            onPressed: problem != null || _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(l.customInsightCreate),
          ),
        ],
      ),
    );
  }
}
