import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/models/custom_insight.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/custom_insight_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/insights/custom_insight_form.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/plan_usage_line.dart';

/// The Custom tab of the Insights screen: the user's saved custom reports and,
/// on a plan that has the feature, the button that makes a new one. Without the
/// feature (Free, Plus) the tab says it comes with Pro; reports made earlier
/// (before a downgrade) stay in the list and can still be opened or deleted.
class CustomInsightsTab extends StatefulWidget {
  const CustomInsightsTab({super.key});

  @override
  State<CustomInsightsTab> createState() => _CustomInsightsTabState();
}

class _CustomInsightsTabState extends State<CustomInsightsTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CustomInsightProvider>().load();
    });
  }

  Future<void> _refresh() => context.read<CustomInsightProvider>().load();

  Future<void> _confirmDelete(CustomInsight report) async {
    final l = AppLocalizations.of(context);
    final provider = context.read<CustomInsightProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
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
    if (confirmed != true) return;
    final gone = await provider.delete(report.id);
    if (gone || !mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(customErrorText(l, provider.lastErrorCode, provider.lastError ?? '')),
      backgroundColor: scheme.error,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomInsightProvider>();
    final auth = context.watch<AuthProvider>();
    final plan = context.watch<PlanProvider>();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    // Until the plan has loaded, only Pro is assumed to have the feature.
    final locked = plan.isLocked(PlanFeature.insightCustom, whenUnknown: !auth.isPro);
    final reports = provider.reports;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 130),
        children: [
          if (locked)
            _lockedCard(l, scheme)
          else ...[
            const PlanUsageLine(feature: PlanFeature.insightCustom, padding: EdgeInsets.only(bottom: 8)),
            FilledButton.icon(
              key: const Key('custom-insight-new'),
              onPressed: () => showCustomInsightForm(context),
              icon: const Icon(Icons.auto_awesome_rounded, size: 20),
              label: Text(l.customInsightNew),
            ),
          ],
          const SizedBox(height: 16),
          if (reports.isNotEmpty)
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < reports.length; i++) ...[
                    if (i > 0) const Divider(),
                    _reportRow(reports[i], l, scheme),
                  ],
                ],
              ),
            )
          else if (provider.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (provider.error != null)
            _loadError(provider, l, scheme)
          else if (!locked)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  l.customInsightEmptyList,
                  style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lockedCard(AppLocalizations l, ColorScheme scheme) {
    return Card(
      key: const Key('custom-insight-locked'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(Icons.lock_rounded, size: 28, color: scheme.tertiary),
            const SizedBox(height: 10),
            Text(
              l.customInsightLockedTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              l.customInsightLockedBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('custom-insight-upgrade'),
              onPressed: () => Navigator.pushNamed(context, '/subscription'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 20),
              label: Text(l.customInsightUpgrade),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadError(CustomInsightProvider provider, AppLocalizations l, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            provider.error!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('custom-insight-reload'),
            onPressed: provider.load,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l.tryAgain),
          ),
        ],
      ),
    );
  }

  /// "Being created…", the refusal / failure sentence, or when it was made.
  String _statusText(AppLocalizations l, CustomInsight report) {
    switch (report.status) {
      case CustomInsightStatus.pending:
        return l.customStatusPending;
      case CustomInsightStatus.refused:
        return l.customStatusRefused;
      case CustomInsightStatus.failed:
      case CustomInsightStatus.unknown:
        return l.customStatusFailed;
      case CustomInsightStatus.ready:
        return l.formatPlanDate(report.completedAt ?? report.createdAt);
    }
  }

  Widget _reportRow(CustomInsight report, AppLocalizations l, ColorScheme scheme) {
    final problem = report.status == CustomInsightStatus.refused ||
        report.status == CustomInsightStatus.failed ||
        report.status == CustomInsightStatus.unknown;
    return InkWell(
      key: Key('custom-insight-item-${report.id}'),
      onTap: () => openCustomInsightReport(context, report.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customRangeText(l, report.startDate, report.endDate),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    customInsightTitle(l, report),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (report.isPending) ...[
                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          _statusText(l, report),
                          key: Key('custom-insight-status-${report.id}'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: problem ? scheme.error : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // The server will not delete a report that is still being written.
            if (!report.isPending)
              IconButton(
                key: Key('custom-insight-delete-${report.id}'),
                tooltip: l.customInsightDelete,
                icon: Icon(Icons.delete_outline_rounded, color: scheme.onSurfaceVariant),
                onPressed: () => _confirmDelete(report),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}
