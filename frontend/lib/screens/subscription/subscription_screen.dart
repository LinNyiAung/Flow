import 'package:flutter/material.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/widgets/plan_badge.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../services/localization_service.dart';

/// The Upgrade screen: the user's current plan and a Free / Plus / Pro
/// comparison built from the limits the server reports (`GET /api/plan`), so
/// no number lives in the app, plus the owner's upgrade contact message.
class SubscriptionScreen extends StatefulWidget {
  @override
  _SubscriptionScreenState createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isClaiming = false;

  @override
  void initState() {
    super.initState();
    // The owner may have changed the limits or the contact message since the
    // plan was last loaded.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Provider.of<PlanProvider>(context, listen: false).refresh();
    });
  }

  Future<void> _claimFreeTrial(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final planProvider = Provider.of<PlanProvider>(context, listen: false);
    final localizations = AppLocalizations.of(context);

    setState(() => _isClaiming = true);

    final success = await authProvider.claimFreeTrial();
    // The trial is a Plus plan with its own allowances: load them now.
    if (success) planProvider.refresh();

    if (!mounted) return;
    setState(() => _isClaiming = false);

    if (success) {
      final scheme = Theme.of(context).colorScheme;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.star_rounded, color: scheme.tertiary, size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                localizations.welcomeToPlusCelebration,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                localizations.oneMonthFreePlusAccess,
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(backgroundColor: scheme.tertiary),
                  child: Text(localizations.letsGo),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authProvider.error ?? localizations.couldNotClaimFreeTrial)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Consumer2<AuthProvider, PlanProvider>(
          builder: (context, authProvider, planProvider, child) {
            final isPaid = authProvider.isPaid;
            final hasClaimedTrial = authProvider.hasClaimedFreeTrial;

            return Column(
              children: [
                // ── Header ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          isPaid ? localizations.yourPlanTitle : localizations.upgradePlan,
                          style: theme.textTheme.titleLarge?.copyWith(color: scheme.onSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: RefreshIndicator(
                    onRefresh: planProvider.refresh,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Current plan card ─────────────────────────
                          if (isPaid) ...[
                            _buildCurrentPlanCard(context, authProvider, scheme, localizations),
                            const SizedBox(height: 28),
                          ],

                          // ── Free-month offer (leads, per redesign) ──
                          if (!isPaid && !hasClaimedTrial) ...[
                            _buildOfferHero(context, scheme),
                            const SizedBox(height: 28),
                          ],

                          // ── Free / Plus / Pro, from the server's limits ──
                          Text(
                            localizations.comparePlans,
                            style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurface),
                          ),
                          const SizedBox(height: 12),
                          _buildComparison(context, planProvider, authProvider.plan, localizations),

                          // ── Upgrade contact (the only path to upgrade) ──
                          if (!authProvider.isPro) ...[
                            const SizedBox(height: 24),
                            _buildContactBox(context, planProvider.status, localizations),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── The user's current paid plan ───────────────────────────────────────────
  Widget _buildCurrentPlanCard(
    BuildContext context,
    AuthProvider authProvider,
    ColorScheme scheme,
    AppLocalizations localizations,
  ) {
    final planName = localizations.planName(authProvider.plan);
    final isTrial = authProvider.isTrial;
    final expiresAt = authProvider.subscriptionExpiresAt;
    final endDate = authProvider.trialEndsAt ?? expiresAt;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(Icons.star_rounded, color: scheme.tertiary, size: 44),
          const SizedBox(height: 14),
          Text(
            isTrial ? localizations.planTrialActive(planName) : localizations.planActive(planName),
            key: const Key('current-plan-title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: scheme.onTertiaryContainer,
            ),
          ),
          if (endDate != null) ...[
            const SizedBox(height: 6),
            Text(
              isTrial
                  ? localizations.planTrialEnds(DateFormat('MMM dd, yyyy').format(endDate))
                  : '${localizations.expiresOn}: ${DateFormat('MMM dd, yyyy').format(endDate)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onTertiaryContainer),
            ),
          ],
        ],
      ),
    );
  }

  // ── "One month free" tonal hero ────────────────────────────────────────────
  Widget _buildOfferHero(BuildContext context, ColorScheme scheme) {
    final localizations = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizations.oneMonthFreeCaps,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 8),
          Text(
            localizations.letAppReadYourMoney,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer, height: 1.25),
          ),
          const SizedBox(height: 8),
          Text(
            localizations.weeklyInsightsReceiptScanningVoiceAiBudgets,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onPrimaryContainer, height: 1.4),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isClaiming ? null : () => _claimFreeTrial(context),
              icon: _isClaiming
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.card_giftcard_rounded, size: 20),
              label: Text(_isClaiming ? localizations.claiming : localizations.claimOneMonthFree),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              localizations.noCardRequiredThenContactUs,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  // ── Free / Plus / Pro comparison ───────────────────────────────────────────
  Widget _buildComparison(
    BuildContext context,
    PlanProvider planProvider,
    Plan currentPlan,
    AppLocalizations localizations,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final status = planProvider.status;
    if (status == null || status.catalog.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: planProvider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Text(
                    localizations.planDetailsUnavailable,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: planProvider.refresh,
                    child: Text(localizations.tryAgain),
                  ),
                ],
              ),
      );
    }
    return PlanComparisonTable(
      catalog: status.catalog,
      currentPlan: currentPlan,
    );
  }

  // ── Upgrade contact info box ───────────────────────────────────────────────
  Widget _buildContactBox(BuildContext context, PlanStatus? status, AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    final message = status?.contactMessage(Localizations.localeOf(context).languageCode) ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.outlineVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.chat_bubble_outline_rounded, color: scheme.onSurfaceVariant, size: 26),
          const SizedBox(height: 8),
          Text(
            message.isNotEmpty ? localizations.planContactTitle : localizations.contactAdmin,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            message.isNotEmpty ? message : localizations.contactSupport,
            key: const Key('upgrade-contact-message'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// The Free / Plus / Pro comparison: one row per feature, one column per plan
/// (a number and its period, a tick for "included", a dash for "not
/// included"), with the user's current plan's column highlighted. Everything
/// comes from [catalog], the limits the server reports.
class PlanComparisonTable extends StatelessWidget {
  const PlanComparisonTable({
    super.key,
    required this.catalog,
    required this.currentPlan,
  });

  final Map<Plan, Map<String, CatalogLimit>> catalog;
  final Plan currentPlan;

  static const List<Plan> _plans = [Plan.free, Plan.plus, Plan.pro];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final features = PlanFeature.all
        .where((f) => _plans.any((p) => catalog[p]?.containsKey(f) ?? false))
        .toList();
    final highlight = scheme.primaryContainer.withValues(alpha: 0.55);

    Widget cell(Widget child, Plan? plan, {Alignment alignment = Alignment.center}) {
      return Container(
        color: plan == currentPlan ? highlight : null,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        alignment: alignment,
        child: child,
      );
    }

    final rows = <TableRow>[
      TableRow(
        children: [
          cell(const SizedBox.shrink(), null),
          for (final plan in _plans)
            cell(
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.planName(plan),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (plan == currentPlan) ...[
                    const SizedBox(height: 2),
                    Text(
                      l.planCurrent,
                      key: const Key('current-plan-marker'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
              plan,
            ),
        ],
      ),
      for (final feature in features)
        TableRow(
          children: [
            cell(
              Text(
                l.planFeatureName(feature),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              null,
              alignment: Alignment.centerLeft,
            ),
            for (final plan in _plans)
              cell(_limitCell(context, l, scheme, catalog[plan]?[feature]), plan),
          ],
        ),
    ];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Theme.of(context).cardTheme.shadowColor ?? Colors.black12, blurRadius: 3, offset: const Offset(0, 1)),
        ],
      ),
      child: Table(
        key: const Key('plan-comparison-table'),
        // Every cell is as tall as the row's tallest, so the current plan's
        // highlight fills the whole column.
        defaultVerticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
        columnWidths: const {
          0: FlexColumnWidth(2.1),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
          3: FlexColumnWidth(1),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: scheme.outlineVariant),
        ),
        children: rows,
      ),
    );
  }

  Widget _limitCell(
    BuildContext context,
    AppLocalizations l,
    ColorScheme scheme,
    CatalogLimit? limit,
  ) {
    if (limit == null || limit.isLocked) {
      return Semantics(
        label: l.planNotIncluded,
        child: Icon(Icons.remove_rounded, size: 20, color: scheme.outline),
      );
    }
    if (limit.isIncluded || limit.quota == null) {
      return Semantics(
        label: l.planIncluded,
        child: Icon(Icons.check_rounded, size: 20, color: scheme.primary),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${limit.quota}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        Text(
          limit.period == 'week' ? l.planPerWeek : l.planPerMonth,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
