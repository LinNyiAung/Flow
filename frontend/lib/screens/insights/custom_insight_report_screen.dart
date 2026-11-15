import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import 'package:frontend/models/custom_insight.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/custom_insight_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/custom_insight_text.dart';
import 'package:frontend/utils/safe_markdown.dart';
import 'package:frontend/widgets/app_bar_title.dart';
import 'package:frontend/widgets/custom_insight_figures.dart';
import 'package:frontend/widgets/insight_markdown.dart';
import 'package:frontend/widgets/mascot.dart';
import 'package:frontend/widgets/plan_limit_sheet.dart';

/// One saved custom insight: what was asked, the figures of the range and the
/// written report, in English or (when it exists or can be made) Myanmar.
class CustomInsightReportScreen extends StatefulWidget {
  const CustomInsightReportScreen({super.key, required this.reportId});

  final String reportId;

  @override
  State<CustomInsightReportScreen> createState() => _CustomInsightReportScreenState();
}

class _CustomInsightReportScreenState extends State<CustomInsightReportScreen> {
  bool _loading = true;

  /// The report is gone (deleted, or never the user's): the provider's 404.
  bool _notFound = false;

  /// The last open failed for another reason.
  bool _failed = false;

  /// 'en' | 'mm'. Always starts on English; opening never translates.
  String _language = 'en';
  bool _translating = false;

  /// A delete is under way: the cached report disappears on purpose.
  bool _deleting = false;
  CustomInsight? _lastReport;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final provider = context.read<CustomInsightProvider>();
    setState(() {
      _loading = true;
      _failed = false;
      _notFound = false;
    });
    final report = await provider.open(widget.reportId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _notFound = report == null && provider.notFound;
      _failed = report == null && !provider.notFound;
    });
  }

  /// True when the plan has no translation (always for Free), so a report
  /// without a stored Myanmar text cannot get one.
  bool _translationLocked() {
    final isPaid = context.read<AuthProvider>().isPaid;
    return !isPaid || context.read<PlanProvider>().isLocked(PlanFeature.insightTranslation);
  }

  Future<void> _selectLanguage(CustomInsight report, String language) async {
    if (language == _language || _translating) return;
    if (language == 'en' || report.contentMm != null) {
      setState(() => _language = language);
      return;
    }
    if (_translationLocked()) {
      await Navigator.pushNamed(context, '/subscription');
      return;
    }
    final provider = context.read<CustomInsightProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    setState(() => _translating = true);
    final result = await provider.translate(report.id);
    if (!mounted) return;
    setState(() {
      _translating = false;
      if (result?.contentMm != null) _language = 'mm';
    });
    if (result != null) return;
    final limit = provider.lastPlanLimit;
    if (limit != null) {
      await showPlanLimitSheet(context, limit);
      return;
    }
    messenger.showSnackBar(SnackBar(
      content: Text(customErrorText(l, provider.lastErrorCode, provider.lastError ?? '')),
      backgroundColor: scheme.error,
    ));
  }

  Future<void> _confirmDelete(CustomInsight report) async {
    final l = AppLocalizations.of(context);
    final provider = context.read<CustomInsightProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (!await confirmDeleteCustomInsight(context)) return;
    _deleting = true;
    final gone = await provider.delete(report.id);
    if (gone) {
      // Stays true: the route is leaving, and the report that is going away
      // must not be fetched again or replaced by a spinner meanwhile.
      if (navigator.mounted) navigator.pop();
      return;
    }
    _deleting = false;
    messenger.showSnackBar(SnackBar(
      content: Text(customErrorText(l, provider.lastErrorCode, provider.lastError ?? '')),
      backgroundColor: scheme.error,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomInsightProvider>();
    context.watch<AuthProvider>();
    context.watch<PlanProvider>();
    final l = AppLocalizations.of(context);
    // While it is being deleted the report is still shown (not a spinner) until
    // the route has left.
    final report = provider.detail(widget.reportId) ?? (_deleting ? _lastReport : null);
    _lastReport = report;

    // A report that was still being written had its cached copy dropped when
    // the list saw it finish: fetch the finished one.
    if (report == null && !_loading && !_notFound && !_failed && !_deleting) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(l.aiInsights),
        actions: [
          if (report != null && !report.isPending)
            IconButton(
              key: const Key('custom-report-delete'),
              tooltip: l.customInsightDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _confirmDelete(report),
            ),
        ],
      ),
      body: _body(report, l),
    );
  }

  Widget _body(CustomInsight? report, AppLocalizations l) {
    final scheme = Theme.of(context).colorScheme;
    if (_notFound) {
      return _message(
        icon: Icons.delete_outline_rounded,
        text: l.customReportDeleted,
        key: const Key('custom-report-deleted'),
      );
    }
    if (report == null) {
      if (_failed) {
        final provider = context.read<CustomInsightProvider>();
        return _message(
          icon: Icons.error_outline_rounded,
          pose: MascotPose.forError(provider.lastError),
          text: customErrorText(l, provider.lastErrorCode, provider.lastError ?? ''),
          action: FilledButton.icon(
            key: const Key('custom-report-retry'),
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l.tryAgain),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    final showMm = _language == 'mm' && report.contentMm != null;
    final text = showMm ? report.contentMm : report.content;
    final figures = report.figures;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        Card(
          key: const Key('custom-report-header'),
          color: scheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 18, color: scheme.tertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        customRangeText(l, report.startDate, report.endDate),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.tertiary),
                      ),
                    ),
                    if (report.isReady) ...[
                      const SizedBox(width: 8),
                      _languageToggle(report, scheme, l),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  customInsightTitle(l, report),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: scheme.onTertiaryContainer),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (report.isPending)
          _statusCard(l.customStatusPending, scheme.onSurfaceVariant, spinner: true)
        else if (!report.isReady)
          _statusCard(
            report.status == CustomInsightStatus.refused ? l.customStatusRefused : l.customStatusFailed,
            scheme.error,
          )
        else ...[
          if (figures != null && figures.currencies.isNotEmpty) ...[
            CustomInsightFigureCards(figures),
            const SizedBox(height: 12),
          ],
          if (text != null && text.trim().isNotEmpty)
            Card(
              key: const Key('custom-report-body'),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: hasDisallowedMarkdown(text)
                    // A table, code or HTML in the text: plain text, never a
                    // broken or unsafe layout.
                    ? SelectableText(
                        markdownToPlainText(text),
                        style: TextStyle(fontSize: 14, height: 1.55, color: scheme.onSurface),
                      )
                    : MarkdownBody(
                        data: text,
                        styleSheet: insightMarkdownStyle(scheme.onSurface, scheme.onSurfaceVariant),
                      ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _statusCard(String text, Color color, {bool spinner = false}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            if (spinner) ...[
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
            ),
          ],
        ),
      ),
    );
  }

  /// A full-page message. With [pose] (a failure with a retry) Ko Toe Pwar
  /// stands in for the [icon].
  Widget _message({required IconData icon, required String text, Key? key, Widget? action, MascotPose? pose}) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          key: key,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pose != null) Mascot(pose, size: 120) else Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      ),
    );
  }

  /// English / မြန်မာ, like the weekly and monthly insight's toggle. မြန်မာ
  /// carries a lock when the report has no stored Myanmar text and the plan
  /// cannot translate one.
  Widget _languageToggle(CustomInsight report, ColorScheme scheme, AppLocalizations l) {
    final mmLocked = report.contentMm == null && _translationLocked();

    Widget seg(String language, String label, {bool lock = false, bool busy = false}) {
      final selected = _language == language;
      return InkWell(
        key: Key('custom-lang-$language'),
        borderRadius: BorderRadius.circular(14),
        onTap: selected ? null : () => _selectLanguage(report, language),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? scheme.tertiary : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (lock) ...[
                Icon(Icons.lock_rounded, size: 12, color: scheme.onTertiaryContainer),
                const SizedBox(width: 4),
              ],
              if (busy) ...[
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? scheme.onTertiary : scheme.onTertiaryContainer,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.tertiary),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('en', l.insightLangEnglish),
          seg('mm', l.insightLangMyanmar, lock: mmLocked, busy: _translating),
        ],
      ),
    );
  }
}
