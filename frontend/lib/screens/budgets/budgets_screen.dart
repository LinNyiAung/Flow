import 'package:flutter/material.dart';
import 'package:frontend/utils/date_format.dart';
import 'package:frontend/widgets/app_bar_title.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/category_icons.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/hero_card.dart';
import 'package:frontend/widgets/progress_meter.dart';
import 'package:frontend/widgets/stat_tile.dart';
import 'package:frontend/widgets/status_pill.dart';
import 'package:provider/provider.dart';
import '../../models/budget.dart';
import '../../providers/budget_provider.dart';
import '../../widgets/app_drawer.dart';
import 'create_budget_screen.dart';
import 'budget_detail_screen.dart';

class BudgetsScreen extends StatefulWidget {
  @override
  _BudgetsScreenState createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _activeOnly = true;
  Currency? _selectedCurrency;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _selectedCurrency = null;
      });
      _refreshData();
    });
  }

  Future<void> _refreshData() async {
    final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);
    await Future.wait([
      budgetProvider.fetchBudgets(
        activeOnly: _activeOnly,
        currency: _selectedCurrency,
      ),
      budgetProvider.fetchMultiCurrencySummary(),
    ]);
  }

  void _navigateToCreateBudget() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateBudgetScreen()),
    );
    final localizations = AppLocalizations.of(context);

    if (result == true) {
      _refreshData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.budgetCreatedSuccessfully)),
      );
    }
  }

  void _navigateToBudgetDetail(Budget budget) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BudgetDetailScreen(budget: budget)),
    );
    final localizations = AppLocalizations.of(context);

    if (result != null) {
      _refreshData();
      if (result == 'deleted') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.budgetDeletedSuccessfully)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final budgetProvider = Provider.of<BudgetProvider>(context);
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: AppBarTitle(localizations.budgets),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, notificationProvider, child) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_rounded),
                    onPressed: () {
                      Navigator.pushNamed(context, '/notifications').then((_) {
                        notificationProvider.fetchUnreadCount();
                      });
                    },
                  ),
                  if (notificationProvider.unreadCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          notificationProvider.unreadCount > 9
                              ? '9+'
                              : '${notificationProvider.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        color: scheme.primary,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _buildSummaryHero(budgetProvider, localizations),
              ),
            ),
            SliverToBoxAdapter(child: const SizedBox(height: 16)),
            SliverToBoxAdapter(child: _buildFilterRow(localizations)),
            SliverToBoxAdapter(child: const SizedBox(height: 16)),
            if (budgetProvider.isLoading)
              SliverToBoxAdapter(
                child: Container(
                  height: 200,
                  alignment: Alignment.center,
                  child: CircularProgressIndicator(color: scheme.primary),
                ),
              )
            else if (budgetProvider.budgets.isEmpty)
              SliverToBoxAdapter(child: _buildEmptyState(localizations))
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final budget = budgetProvider.budgets[index];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _buildBudgetCard(context, budget, localizations),
                  );
                }, childCount: budgetProvider.budgets.length),
              ),
            SliverToBoxAdapter(child: const SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreateBudget,
        tooltip: localizations.createNewBudget,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildSummaryHero(
    BudgetProvider budgetProvider,
    AppLocalizations localizations,
  ) {
    final multi = budgetProvider.multiCurrencySummary;

    final stats = <Widget>[
      StatTile(
        icon: Icons.trending_up_rounded,
        label: localizations.active,
        value: '${multi?.activeBudgets ?? 0}',
        stacked: true,
      ),
      StatTile(
        // Not `localizations.exceeded` ("Exceeded") here — three equal-width
        // stat tiles don't have room for it and it truncates to "Exceed…";
        // the same key is fine as the full-width status pill elsewhere.
        icon: Icons.warning_amber_rounded,
        label: localizations.overShort,
        value: '${multi?.exceededBudgets ?? 0}',
        iconColor: Theme.of(context).colorScheme.error,
        stacked: true,
      ),
      StatTile(
        icon: Icons.dashboard_rounded,
        label: localizations.total,
        value: '${multi?.totalBudgets ?? 0}',
        stacked: true,
      ),
    ];

    CurrencyBudgetSummary? summary;
    if (multi != null) {
      summary = _selectedCurrency != null
          ? multi.getSummaryForCurrency(_selectedCurrency!)
          : (multi.currencySummaries.isNotEmpty ? multi.currencySummaries.first : null);
    }

    if (summary == null) {
      return HeroCard(
        label: localizations.budgetSummary,
        value: '${multi?.totalBudgets ?? 0}',
        supporting: localizations.noBudgetsYet,
        stats: stats,
      );
    }

    return HeroCard(
      label: '${localizations.budgetSummary} · ${summary.currency.name.toUpperCase()}',
      value: summary.displayTotalSpent,
      supporting:
          '${localizations.total} ${summary.displayTotalAllocated} · ${summary.percentageUsed.toStringAsFixed(0)}% ${localizations.used}',
      stats: stats,
      // Same "% Used" figure from the supporting line above, drawn as a bar
      // — kept inside the card (via HeroCard's footer slot) so it reads as
      // part of the figure it's illustrating, not a disconnected element.
      footer: ProgressMeter(value: summary.percentageUsed / 100, onHero: true),
    );
  }

  Widget _buildFilterRow(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    // Wraps onto a second line when the chips don't fit (e.g. Myanmar at
    // 360 px), so the currency filter is never clipped off the edge.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _filterChip(localizations.active, _activeOnly, () {
            setState(() => _activeOnly = true);
            _refreshData();
          }),
          _filterChip(localizations.filterChipAll, !_activeOnly, () {
            setState(() => _activeOnly = false);
            _refreshData();
          }),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 1,
            height: 20,
            color: scheme.outlineVariant,
          ),
          _currencyFilterChip(),
        ],
      ),
    );
  }

  // One dropdown chip for currency, rather than a whole second row of
  // per-currency choice chips.
  Widget _currencyFilterChip() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final label = _selectedCurrency == null
        ? localizations.allCurrencies
        : '${_selectedCurrency!.symbol} ${_selectedCurrency!.name.toUpperCase()}';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _pickCurrencyFilter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.currency_exchange_rounded, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            // Flexible: a label longer than the row wraps inside the chip.
            Flexible(
              child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _pickCurrencyFilter() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final options = <Currency?>[null, ...Currency.values];

    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(localizations.currency, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final currency in options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                currency == null
                    ? localizations.allCurrencies
                    : '${currency.symbol} ${currency.name.toUpperCase()} · ${currency.displayName}',
              ),
              trailing: _selectedCurrency == currency
                  ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                  : null,
              onTap: () {
                setState(() => _selectedCurrency = currency);
                Navigator.pop(sheetContext);
                _refreshData();
              },
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? scheme.primary : scheme.outline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : scheme.onSurface,
          ),
        ),
      ),
    );
  }

  _StatusMeta _statusMeta(Budget budget, AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    if (budget.isUpcoming || budget.status == BudgetStatus.upcoming) {
      return _StatusMeta(
        tint: AppTheme.infoContainerFor(context),
        ink: AppTheme.infoFor(context),
        label: localizations.upcoming,
      );
    }
    switch (budget.status) {
      case BudgetStatus.exceeded:
        return _StatusMeta(
          tint: scheme.errorContainer,
          ink: scheme.error,
          // Only some categories over (the total isn't): say so, rather than
          // "EXCEEDED" next to e.g. "16%".
          label: budget.onlyCategoriesOver
              ? localizations.categoriesOverBadge(budget.categoriesOver.length)
              : localizations.exceededCap,
        );
      case BudgetStatus.completed:
        return _StatusMeta(
          tint: scheme.secondaryContainer,
          ink: scheme.onSurfaceVariant,
          label: localizations.completed,
        );
      default:
        return _StatusMeta(
          tint: scheme.primaryContainer,
          ink: scheme.primary,
          label: localizations.activeCap,
        );
    }
  }

  Widget _buildBudgetCard(
    BuildContext context,
    Budget budget,
    AppLocalizations localizations,
  ) {
    final meta = _statusMeta(budget, localizations);

    return GestureDetector(
      onTap: () => _navigateToBudgetDetail(budget),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Theme.of(context).cardTheme.shadowColor ?? const Color(0x14101815), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: meta.tint, shape: BoxShape.circle),
                  child: Icon(
                    budget.autoCreateWithAi ? Icons.auto_awesome_rounded : iconForCategoryName(budget.name),
                    size: 20,
                    color: meta.ink,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Two lines, so the status badge doesn't squeeze
                          // the name down to "Monthly ess…".
                          Expanded(
                            child: Text(
                              budget.name,
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!budget.isUpcoming) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${budget.percentageUsed.toStringAsFixed(0)}%',
                              style: AppTheme.money(13, weight: FontWeight.w700, color: meta.ink),
                            ),
                          ],
                          const SizedBox(width: 8),
                          // Capped so a long label (e.g. "2 CATEGORIES OVER"
                          // in Myanmar) wraps inside the pill instead of
                          // pushing the row past the card at 360 px.
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: StatusPill(label: meta.label, background: meta.tint, foreground: meta.ink),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${localizations.budgetPeriodLabel(budget.period).toUpperCase()} · ${budget.currency.name.toUpperCase()}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (budget.isUpcoming) ...[
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.infoFor(context)),
                  const SizedBox(width: 6),
                  Text(
                    '${localizations.startsOnPrefix} ${AppDates.full(context, budget.startDate)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.infoFor(context),
                    ),
                  ),
                ],
              ),
            ] else ...[
              ProgressMeter(value: budget.percentageUsed / 100, overrideColor: meta.ink),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      budget.displayTotalSpent,
                      style: AppTheme.money(15, weight: FontWeight.w700, color: meta.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      budget.isTotalOver
                          ? localizations.overByAmount(
                              '${budget.currency.symbol}${formatter.format(budget.totalSpent - budget.totalBudget)}')
                          : '${localizations.remaining} ${budget.displayRemainingBudget}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: budget.isTotalOver ? FontWeight.w700 : FontWeight.w500,
                        color: budget.isTotalOver
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.savings_rounded, size: 40, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              localizations.noBudgetsYet,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              localizations.createYourFirstBudget,
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusMeta {
  const _StatusMeta({required this.tint, required this.ink, required this.label});

  final Color tint;
  final Color ink;
  final String label;
}
