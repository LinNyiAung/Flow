import 'package:flutter/material.dart';
import 'package:frontend/screens/budgets/edit_budget_screen.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/category_icons.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/progress_meter.dart';
import 'package:frontend/widgets/status_pill.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/budget.dart';
import '../../providers/budget_provider.dart';

import '../../services/localization_service.dart';

class BudgetDetailScreen extends StatefulWidget {
  final Budget budget;

  BudgetDetailScreen({required this.budget});

  @override
  _BudgetDetailScreenState createState() => _BudgetDetailScreenState();
}

class _BudgetDetailScreenState extends State<BudgetDetailScreen> {
  late Budget _budget;
  bool _isRefreshing = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _budget = widget.budget;
    _refreshBudget();
  }

  Future<void> _refreshBudget() async {
    setState(() => _isRefreshing = true);

    final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);

    // Ask the backend to recompute this budget's spent/remaining figures from
    // the latest transactions (POST /budgets/{id}/refresh) before pulling the
    // now-current record. This runs automatically on load and on pull-to-
    // refresh — there is no user-facing "refresh" button.
    await budgetProvider.refreshBudget(_budget.id);
    final updatedBudget = await budgetProvider.getBudget(_budget.id);

    if (updatedBudget != null) {
      setState(() {
        _budget = updatedBudget;
      });
    }

    setState(() => _isRefreshing = false);
  }

  void _showDeleteConfirmation() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.delete_rounded, color: scheme.error, size: 26),
                ),
                const SizedBox(height: 14),
                Text(
                  '${localizations.deleteBudget}?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  localizations.deleteBudgetAlert,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: scheme.error),
                    onPressed: _isDeleting
                        ? null
                        : () async {
                            setSheetState(() {
                              _isDeleting = true;
                            });
                            setState(() {
                              _isDeleting = true;
                            });

                            await _deleteBudget(sheetContext);

                            if (mounted) {
                              setState(() {
                                _isDeleting = false;
                              });
                            }
                          },
                    child: _isDeleting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(localizations.delete),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _isDeleting ? null : () => Navigator.pop(sheetContext),
                    child: Text(localizations.dialogCancel),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Deletes the budget, then returns to the caller exactly once. Closes
  /// this confirmation sheet on its own route, and — only on success — pops
  /// this screen with [_deletedResultValue] so `budgets_screen.dart` (which
  /// awaits `Navigator.push(...)`) sees the result and shows its own
  /// confirmation. Previously this popped twice — once here with a result,
  /// then again unconditionally in the caller — which silently discarded
  /// the result (and the localized value used for it didn't match the
  /// literal the list screen checked for outside English anyway).
  static const String _deletedResultValue = 'deleted';

  Future<void> _deleteBudget(BuildContext sheetContext) async {
    final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);
    final success = await budgetProvider.deleteBudget(_budget.id);
    final localizations = AppLocalizations.of(context);

    if (success) {
      Navigator.pop(sheetContext);
      Navigator.pop(context, _deletedResultValue);
    } else {
      Navigator.pop(sheetContext);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(budgetProvider.error ?? localizations.failedToDeleteBudget)),
      );
    }
  }

  String _calculateDaysRemaining() {
    final now = DateTime.now().toUtc();
    final startDate = _budget.startDate.toUtc();
    final endDate = _budget.endDate.toUtc();

    if (now.isBefore(startDate)) {
      final daysUntilStart = startDate.difference(now).inDays;
      return 'Starts in $daysUntilStart days';
    }

    if (now.isAfter(endDate)) {
      final daysEnded = now.difference(endDate).inDays;
      return 'Ended $daysEnded days ago';
    }

    final daysRemaining = endDate.difference(now).inDays;
    return '$daysRemaining days remaining';
  }

  // Same three states as _calculateDaysRemaining(), but without repeating the
  // verb the info row's own label ("Starts In" / "Ended" / "Days Remaining")
  // already says — used only there, to avoid rows reading like "Days
  // Remaining: 20 days remaining".
  String _daysRemainingValueOnly() {
    final now = DateTime.now().toUtc();
    final startDate = _budget.startDate.toUtc();
    final endDate = _budget.endDate.toUtc();

    if (now.isBefore(startDate)) {
      return '${startDate.difference(now).inDays} days';
    }
    if (now.isAfter(endDate)) {
      return '${now.difference(endDate).inDays} days ago';
    }
    return '${endDate.difference(now).inDays} days';
  }

  String _getBudgetStatusLabel() {
    final now = DateTime.now().toUtc();
    final startDate = _budget.startDate.toUtc();
    final endDate = _budget.endDate.toUtc();
    final localizations = AppLocalizations.of(context);

    if (now.isBefore(startDate)) {
      return localizations.startsIn;
    } else if (now.isAfter(endDate)) {
      return localizations.ended;
    } else {
      return localizations.daysRemaining;
    }
  }

  void _navigateToEditBudget() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditBudgetScreen(budget: _budget)),
    );

    if (result == true) {
      await _refreshBudget();
    }
  }

  Color _getStatusColor() {
    if (_budget.isUpcoming) {
      return AppTheme.infoFor(context);
    }

    final scheme = Theme.of(context).colorScheme;
    switch (_budget.status) {
      case BudgetStatus.exceeded:
        return scheme.error;
      case BudgetStatus.completed:
        return scheme.onSurfaceVariant;
      case BudgetStatus.upcoming:
        return AppTheme.infoFor(context);
      default:
        return scheme.primary;
    }
  }

  String _getStatusLabel() {
    final localizations = AppLocalizations.of(context);
    if (_budget.isUpcoming) {
      return localizations.upcoming;
    }

    return _budget.status.name.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.budgetDetails),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: _isDeleting ? null : () => _navigateToEditBudget(),
          ),
          IconButton(
            icon: _isDeleting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(scheme.error),
                    ),
                  )
                : Icon(Icons.delete_rounded, color: scheme.error),
            onPressed: _isDeleting ? null : _showDeleteConfirmation,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isRefreshing) LinearProgressIndicator(minHeight: 2, color: scheme.primary),
          Expanded(child: _buildBody(context, scheme, statusColor, localizations)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ColorScheme scheme,
    Color statusColor,
    AppLocalizations localizations,
  ) {
    return RefreshIndicator(
        onRefresh: _refreshBudget,
        color: scheme.primary,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: [
            // Hero overview card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                        // Category icon, not a status icon — the StatusPill
                        // to the right of this row already says ACTIVE /
                        // EXCEEDED / etc., so an icon repeating that (e.g.
                        // the same trending-up glyph on every active budget)
                        // just looks identical across every budget's detail.
                        child: Icon(iconForCategoryName(_budget.name), color: statusColor, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _budget.name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: scheme.onPrimaryContainer,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_budget.period.name.toUpperCase()} · ${_calculateDaysRemaining()}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.onPrimaryContainer.withValues(alpha: 0.82),
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusPill(
                        label: _getStatusLabel(),
                        background: scheme.surface,
                        foreground: statusColor,
                      ),
                    ],
                  ),
                  if (_budget.description != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _budget.description!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.jadeLabelFor(context),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _budget.displayTotalSpent,
                        style: AppTheme.money(32, weight: FontWeight.w800, color: scheme.onPrimaryContainer),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'of ${_budget.displayTotalBudget}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: scheme.onPrimaryContainer.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ProgressMeter(
                    value: _budget.percentageUsed / 100,
                    height: 8,
                    onHero: true,
                    overrideColor: statusColor,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '${_budget.percentageUsed.toStringAsFixed(0)}% ${localizations.used}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer.withValues(alpha: 0.82),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${localizations.remaining}: ${_budget.displayRemainingBudget}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Over-limit / near-limit banners
            if (_budget.status == BudgetStatus.exceeded) ...[
              const SizedBox(height: 16),
              _buildBanner(
                icon: Icons.warning_rounded,
                iconColor: scheme.error,
                background: scheme.errorContainer,
                titleColor: scheme.onErrorContainer,
                title: localizations.budgetExceeded,
                body: localizations.budgetExceededAlert,
              ),
            ] else if (_budget.percentageUsed > 80) ...[
              const SizedBox(height: 16),
              _buildBanner(
                icon: Icons.info_rounded,
                iconColor: scheme.tertiary,
                background: scheme.tertiaryContainer,
                titleColor: scheme.onTertiaryContainer,
                title: localizations.approachingBudgetLimit,
                body:
                    'You\'ve used ${_budget.percentageUsed.toStringAsFixed(0)}% of your budget. Track your spending carefully.',
              ),
            ],

            // Auto-create explanations
            if (_budget.isAutoCreated) ...[
              const SizedBox(height: 16),
              _buildAutoRow(
                title: _budget.autoCreateWithAi
                    ? localizations.budgetWasAutomaticallyCreatedAi
                    : localizations.budgetWasAutomaticallyCreatedPrevious,
              ),
            ],

            if (_budget.autoCreateEnabled) ...[
              const SizedBox(height: 16),
              _buildAutoRow(
                title: localizations.autoCreateEnabled,
                subtitle: _budget.autoCreateWithAi
                    ? localizations.nextBudgetWillBeAiOptimized
                    : localizations.nextBudgetWillUseSameAmounts,
              ),
            ],

            // Upcoming / ended notices
            if (_budget.isUpcoming) ...[
              const SizedBox(height: 16),
              _buildBanner(
                icon: Icons.info_outline_rounded,
                iconColor: AppTheme.infoFor(context),
                background: AppTheme.infoContainerFor(context),
                titleColor: AppTheme.infoFor(context),
                title:
                    'This budget will start on ${DateFormat('MMMM dd, yyyy').format(_budget.startDate)}. No spending is tracked yet.',
                body: null,
              ),
            ] else if (!_budget.isActive &&
                DateTime.now().toUtc().isAfter(_budget.endDate.toUtc())) ...[
              const SizedBox(height: 16),
              _buildBanner(
                icon: Icons.check_circle_rounded,
                iconColor: scheme.onSurfaceVariant,
                background: scheme.secondaryContainer,
                titleColor: scheme.onSurface,
                title: 'This budget ended on ${DateFormat('MMMM dd, yyyy').format(_budget.endDate)}',
                body: null,
              ),
            ],

            const SizedBox(height: 20),

            // Period info
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Theme.of(context).cardTheme.shadowColor ?? const Color(0x14101815), blurRadius: 8, offset: Offset(0, 1)),
                ],
              ),
              child: Column(
                children: [
                  _buildInfoRow(
                    Icons.event_available_rounded,
                    localizations.startDate,
                    DateFormat('MMMM dd, yyyy').format(_budget.startDate),
                  ),
                  const Divider(height: 1, indent: 52),
                  _buildInfoRow(
                    Icons.event_busy_rounded,
                    localizations.endDateNoOp,
                    DateFormat('MMMM dd, yyyy').format(_budget.endDate),
                  ),
                  const Divider(height: 1, indent: 52),
                  _buildInfoRow(
                    Icons.timelapse_rounded,
                    _getBudgetStatusLabel(),
                    _daysRemainingValueOnly(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Category caps
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    localizations.categoryBudgets,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${_budget.categoryBudgets.length} ${localizations.categories}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._budget.categoryBudgets.map((catBudget) => _buildCategoryCard(catBudget, localizations)),
          ],
        ),
    );
  }

  Widget _buildBanner({
    required IconData icon,
    required Color iconColor,
    required Color background,
    required Color titleColor,
    required String title,
    String? body,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: titleColor),
                ),
                if (body != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: titleColor, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoRow({required String title, String? subtitle}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Theme.of(context).cardTheme.shadowColor ?? const Color(0x14101815), blurRadius: 8, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.autorenew_rounded, color: scheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface)),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(CategoryBudget catBudget, AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = catBudget.isExceeded
        ? scheme.error
        : catBudget.percentageUsed > 80
        ? scheme.tertiary
        : scheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Theme.of(context).cardTheme.shadowColor ?? const Color(0x14101815), blurRadius: 8, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer, shape: BoxShape.circle),
                child: Icon(iconForCategoryName(catBudget.mainCategory), color: statusColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  catBudget.mainCategory,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (catBudget.isExceeded) ...[
                StatusPill(
                  label: localizations.exceeded.toUpperCase(),
                  background: scheme.errorContainer,
                  foreground: scheme.error,
                  dense: true,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                '${catBudget.percentageUsed.toStringAsFixed(0)}%',
                style: AppTheme.money(13, weight: FontWeight.w700, color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ProgressMeter(value: catBudget.percentageUsed / 100, overrideColor: statusColor),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '${_budget.currency.symbol}${formatter.format(catBudget.spentAmount)} / ${_budget.currency.symbol}${formatter.format(catBudget.allocatedAmount)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${localizations.remaining}: ${_budget.currency.symbol}${formatter.format(catBudget.allocatedAmount - catBudget.spentAmount)}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
