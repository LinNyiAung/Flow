import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/progress_meter.dart';
import 'package:frontend/widgets/status_pill.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/goal.dart';
import '../../providers/goal_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/app_drawer.dart';
import 'add_goal_screen.dart';
import 'goal_detail_screen.dart';

/// Mockup's `--accent`: identical to `--primary` in light, but a distinct,
/// brighter teal in dark (used for icon tints, meter fills, percentage
/// labels sitting on tonal/card surfaces). `scheme.primary` alone reads too
/// dark in dark mode wherever the mockup specifies `var(--accent)`.
Color _accentColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark ? theme.colorScheme.secondary : theme.colorScheme.primary;
}

class GoalsScreen extends StatefulWidget {
  @override
  _GoalsScreenState createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  GoalStatus? _filterStatus;
  Currency _selectedCurrency = Currency.usd;
  final _formatter = NumberFormat("#,##0.00", "en_US");

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      setState(() {
        _selectedCurrency = authProvider.defaultCurrency;
      });
      _refreshData();
    });
  }

  Future<void> _refreshData() async {
    final goalProvider = Provider.of<GoalProvider>(context, listen: false);
    final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
    await Future.wait([
      // Scoped to the selected currency so the list below always matches
      // the currency the hero above is summarizing.
      goalProvider.fetchGoals(statusFilter: _filterStatus, currency: _selectedCurrency),
      goalProvider.fetchMultiCurrencySummary(), // CHANGED from fetchSummary
      transactionProvider.fetchBalance(currency: _selectedCurrency), // ADD currency parameter
    ]);
  }

  void _navigateToAddGoal() async {
    final localizations = AppLocalizations.of(context);
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddGoalScreen()),
    );

    if (result == true) {
      _refreshData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.goalCreatedSuccessfully),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _navigateToGoalDetail(Goal goal) async {
    final localizations = AppLocalizations.of(context);
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GoalDetailScreen(goal: goal)),
    );

    if (result != null) {
      _refreshData();
      if (result == 'deleted') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.goalDeletedSuccessfully),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final goalProvider = Provider.of<GoalProvider>(context);
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final multiSummary = goalProvider.multiCurrencySummary;
    final currencySummary = multiSummary?.getSummaryForCurrency(_selectedCurrency);

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(localizations.financialGoals),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, notificationProvider, child) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_rounded),
                      onPressed: () {
                        Navigator.pushNamed(context, '/notifications');
                      },
                    ),
                    if (notificationProvider.unreadCount > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            notificationProvider.unreadCount > 9 ? '9+' : '${notificationProvider.unreadCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        color: scheme.primary,
        child: CustomScrollView(
          slivers: [
            // Summary card — matches the mockup's Goals screen exactly: a
            // plain elevated card (NOT the tonal primaryContainer hero used
            // on Dashboard/Budgets/Goal detail — the prototype deliberately
            // uses `var(--card)` + radius 16 here, not `var(--p-container)`
            // + radius 24). Real goal totals for the selected currency; a
            // tappable currency badge reaches every other currency's totals
            // via the picker sheet below (this app supports multiple
            // currencies, unlike the single-currency prototype).
            if (multiSummary != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Saved towards goals',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                              ),
                              InkWell(
                                onTap: _showAllCurrencyBalancesBottomSheet,
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _selectedCurrency.name.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.2,
                                          color: scheme.onPrimaryContainer,
                                        ),
                                      ),
                                      Icon(Icons.expand_more_rounded, size: 14, color: scheme.onPrimaryContainer),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                _selectedCurrency.symbol,
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                currencySummary != null ? _formatter.format(currencySummary.totalAllocated) : '0.00',
                                style: AppTheme.money(32, weight: FontWeight.w800, color: scheme.onSurface),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currencySummary != null
                                ? 'of ${_selectedCurrency.symbol}${_formatter.format(currencySummary.totalTarget)}'
                                    ' · ${currencySummary.activeGoals + currencySummary.achievedGoals} ${localizations.goals}'
                                : 'of ${_selectedCurrency.symbol}0.00',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 14),
                          ProgressMeter(
                            value: currencySummary != null ? currencySummary.overallProgress / 100 : 0,
                            height: 8,
                            overrideColor: _accentColor(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            SliverToBoxAdapter(child: const SizedBox(height: 20)),

            // Filter Chips
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildFilterChip(localizations.filterChipAll, null),
                    const SizedBox(width: 8),
                    _buildFilterChip(localizations.active, GoalStatus.active),
                    const SizedBox(width: 8),
                    _buildFilterChip(localizations.achieved, GoalStatus.achieved),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(child: const SizedBox(height: 16)),

            // Goals List
            if (goalProvider.isLoading)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator(color: scheme.primary)),
                ),
              )
            else if (goalProvider.goals.isEmpty)
              SliverToBoxAdapter(child: _buildEmptyState())
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final goal = goalProvider.goals[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: _buildGoalCard(goal),
                    );
                  },
                  childCount: goalProvider.goals.length,
                ),
              ),

            SliverToBoxAdapter(child: const SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddGoal,
        tooltip: localizations.createNewGoal,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  void _showAllCurrencyBalancesBottomSheet() async {
    final localizations = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final multiBalances = await ApiService.getAllBalances();
      Navigator.pop(context); // Close loading dialog
      if (!mounted) return;

      await showAppBottomSheet(
        context: context,
        builder: (sheetContext) {
          final scheme = Theme.of(sheetContext).colorScheme;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                    child: Icon(Icons.currency_exchange_rounded, color: scheme.onPrimaryContainer, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(localizations.allCurrencyBalances, style: Theme.of(sheetContext).textTheme.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ...multiBalances.currencies.map((currency) {
                final balance = multiBalances.getBalanceForCurrency(currency);
                if (balance == null) return const SizedBox.shrink();
                final isSelected = _selectedCurrency == currency;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      setState(() => _selectedCurrency = currency);
                      _refreshData();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected ? scheme.primaryContainer : scheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? scheme.primary : scheme.outline,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${currency.symbol} ${currency.displayName}',
                                  style: Theme.of(sheetContext).textTheme.titleMedium,
                                ),
                              ),
                              if (isSelected)
                                StatusPill(
                                  label: localizations.selected.toUpperCase(),
                                  background: scheme.primary,
                                  foreground: Colors.white,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(localizations.availableForGoals, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Text(
                            '${currency.symbol}${_formatter.format(balance.availableBalance)}',
                            style: AppTheme.money(22, weight: FontWeight.w800, color: scheme.onSurface),
                          ),
                          const SizedBox(height: 12),
                          Container(height: 1, color: scheme.outlineVariant),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(localizations.totalBalance, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                  Text(balance.displayBalance, style: AppTheme.money(14, weight: FontWeight.w700, color: scheme.onSurface)),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(localizations.allocatedToGoals, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                  Text(
                                    '${currency.symbol}${_formatter.format(balance.allocatedToGoals)}',
                                    style: AppTheme.money(14, weight: FontWeight.w700, color: scheme.tertiary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      );
    } catch (e) {
      Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load balances: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildFilterChip(String label, GoalStatus? status) {
    final isSelected = _filterStatus == status;
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterStatus = status;
        });
        _refreshData();
      },
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isSelected ? Colors.white : scheme.primary,
      ),
      selectedColor: scheme.primary,
      backgroundColor: scheme.surface,
      side: BorderSide(color: scheme.primary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildGoalCard(Goal goal) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final accent = _accentColor(context);

    IconData goalIcon;
    switch (goal.goalType) {
      case GoalType.savings:
        goalIcon = Icons.savings_rounded;
        break;
      case GoalType.debt_reduction:
        goalIcon = Icons.money_off_rounded;
        break;
      case GoalType.large_purchase:
        goalIcon = Icons.shopping_bag_rounded;
        break;
    }

    final achieved = goal.status == GoalStatus.achieved;
    // Mockup's card subtitle is just the due date ({{ g.due }}) — type is
    // already conveyed by the icon. The list is now scoped to one currency
    // (see _refreshData), so a per-card currency tag is no longer needed
    // either. Fall back to the goal type when there's no target date.
    final subtitle = goal.targetDate != null
        ? 'Due ${DateFormat('MMM dd, yyyy').format(goal.targetDate!)}'
        : goal.goalType.name.replaceAll('_', ' ').toUpperCase();

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _navigateToGoalDetail(goal),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
                    child: Icon(goalIcon, size: 22, color: accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (achieved)
                    StatusPill(
                      label: localizations.achieved.toUpperCase(),
                      background: scheme.primary,
                      foreground: Colors.white,
                    )
                  else
                    Text(
                      '${goal.progressPercentage.toStringAsFixed(0)}%',
                      style: AppTheme.money(14, weight: FontWeight.w700, color: accent),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              ProgressMeter(value: goal.progressPercentage / 100, overrideColor: accent),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: RichText(
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        children: [
                          TextSpan(text: goal.displayCurrentAmount, style: AppTheme.money(14, weight: FontWeight.w700, color: scheme.onSurface)),
                          TextSpan(
                            text: ' / ${goal.displayTargetAmount}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _navigateToGoalDetail(goal),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text(localizations.manageFunds, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.flag_rounded, size: 40, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 20),
          Text(localizations.noGoalsYet, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            localizations.createGoalGetStarted,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
