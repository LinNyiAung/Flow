import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/insight_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/screens/budgets/budget_detail_screen.dart';
import 'package:frontend/screens/transactions/image_input_screen.dart';
import 'package:frontend/screens/transactions/transactions_list_screen.dart';
import 'package:frontend/screens/transactions/voice_input_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/services/notification_event_bus.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/category_icons.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/app_list_row.dart';
import 'package:frontend/widgets/hero_card.dart';
import 'package:frontend/widgets/progress_meter.dart';
import 'package:frontend/widgets/status_pill.dart';
import 'package:frontend/widgets/stat_tile.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/budget_provider.dart';
import '../../models/transaction.dart';
import '../../models/budget.dart';
import '../../models/goal.dart';
import '../transactions/add_transaction_screen.dart';
import '../transactions/edit_transaction_screen.dart'; // Import for editing
import '../../widgets/app_drawer.dart'; // Import the drawer widget
import 'package:frontend/services/responsive_helper.dart';

final formatter = NumberFormat("#,##0.00", "en_US");

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription? _notificationSubscription;
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>(); // Key for the Scaffold to open the drawer

  @override
  void initState() {
    super.initState();
    // Fetch initial data when the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData(); // Fetch transactions and balance

      // NEW: Listen for notification events
      _notificationSubscription = NotificationEventBus().onNotificationReceived
          .listen((_) {
            final notificationProvider = Provider.of<NotificationProvider>(
              context,
              listen: false,
            );
            notificationProvider.fetchUnreadCount();
          });
    });
  }

  // ADD THIS METHOD
  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  // Function to refresh data (pull-to-refresh and initial load)
  Future<void> _refreshData() async {
    final transactionProvider = Provider.of<TransactionProvider>(
      context,
      listen: false,
    );
    final goalProvider = Provider.of<GoalProvider>(context, listen: false);
    final notificationProvider = Provider.of<NotificationProvider>(
      context,
      listen: false,
    );
    final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // Get the current default currency
    final defaultCurrency = authProvider.defaultCurrency;

    await Future.wait([
      // Fetch a bit more than the 3 rows the "Recent" list shows so the
      // Spending pace chart below has real last-7-days data to bucket —
      // the recent-transactions list still only ever renders the first 3.
      transactionProvider.fetchTransactions(limit: 30),
      transactionProvider.fetchBalance(
        currency: defaultCurrency,
      ), // Pass default currency
      goalProvider.fetchSummary(),
      goalProvider.fetchGoals(statusFilter: GoalStatus.active),
      notificationProvider.fetchUnreadCount(),
      budgetProvider.fetchBudgets(activeOnly: true),
      // Just a history GET, not a generation call — safe to prefetch for
      // the "continue chatting" preview below. (Unlike insights: never
      // call InsightProvider.fetchInsights() from here, since that can
      // trigger a real AI generation on the backend when nothing is
      // cached yet — the insight teaser only ever reads whatever's
      // already in InsightProvider from a prior visit this session.)
      chatProvider.loadChatHistory(),
    ]);
  }

  // Function to navigate to the TransactionsListScreen
  void _navigateToTransactionsList() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TransactionsListScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to AuthProvider for user details and TransactionProvider for data
    final authProvider = Provider.of<AuthProvider>(context);
    final transactionProvider = Provider.of<TransactionProvider>(context);
    final localizations = AppLocalizations.of(context);
    final responsive = ResponsiveHelper(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey, // Assign the scaffold key to the Scaffold
      drawer: AppDrawer(), // Add the navigation drawer to the scaffold
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState
              ?.openDrawer(), // Use the key to open the drawer
        ),
        title: Text('Toe Pwar'),
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, notificationProvider, child) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(Icons.notifications_rounded),
                    onPressed: () {
                      Navigator.pushNamed(context, '/notifications').then((
                        _,
                      ) {
                        // Refresh data when returning from notifications
                        notificationProvider.fetchUnreadCount();
                      });
                    },
                  ),
                  if (notificationProvider.unreadCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          // Mockup badges the bell with --primary/--on-primary,
                          // not the error colour.
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                        constraints: BoxConstraints(
                          minWidth: responsive.iconSize(mobile: 16),
                          minHeight: responsive.iconSize(mobile: 16),
                        ),
                        child: Text(
                          '${notificationProvider.unreadCount > 9 ? '9+' : notificationProvider.unreadCount}',
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontSize: responsive.fs10,
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
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/settings'),
            child: Container(
              width: responsive.iconSize(mobile: 40),
              height: responsive.iconSize(mobile: 40),
              margin: EdgeInsets.only(right: responsive.sp12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                authProvider.user?.name != null &&
                        authProvider.user!.name.isNotEmpty
                    ? authProvider.user!.name[0].toUpperCase()
                    : 'U',
                style: TextStyle(
                  fontSize: responsive.fontSize(mobile: 15),
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        // RefreshIndicator allows pull-to-refresh functionality
        child: RefreshIndicator(
          onRefresh: _refreshData,
          child: CustomScrollView(
            // Use CustomScrollView for flexible layouts with slivers
            slivers: [
              // Hero: available-to-spend balance
              SliverToBoxAdapter(
                child: Padding(
                  padding: responsive.padding(horizontal: 16, vertical: 8),
                  child: _buildHero(
                    context,
                    authProvider,
                    transactionProvider,
                    responsive,
                  ),
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: responsive.sp16)),

              // Spending pace: last-7-days outflow, bucketed by day from the
              // real fetched transactions (see mockup lines 97-116).
              SliverToBoxAdapter(
                child: Padding(
                  padding: responsive.padding(horizontal: 16),
                  child: _buildSpendingPace(
                    context,
                    transactionProvider,
                    responsive,
                  ),
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: responsive.sp16)),

              // Recent Transactions Header with "See all" action
              SliverToBoxAdapter(
                child: Padding(
                  padding: responsive.padding(horizontal: 16),
                  child: GestureDetector(
                    onTap: _navigateToTransactionsList,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            localizations.recentTransactions,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontSize: responsive.fs16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: responsive.sp8),
                        Text(
                          localizations.seeMore,
                          style: TextStyle(
                            fontSize: responsive.fs13,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: responsive.icon18,
                          color: scheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: responsive.sp12)),

              // Transactions List (only showing recent ones on Home screen)
              if (transactionProvider.isLoading) // Show loader while fetching
                SliverToBoxAdapter(
                  child: Container(
                    height: 200, // Placeholder height
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (transactionProvider
                  .transactions
                  .isEmpty) // Show empty state
                SliverToBoxAdapter(
                  child: Container(
                    height: 200, // Placeholder height
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long_rounded,
                            size: responsive.icon64,
                            color: scheme.onSurfaceVariant,
                          ),
                          SizedBox(height: responsive.sp16),
                          Text(
                            localizations.noTransactions,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  fontSize: responsive.fs18,
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                          Text(
                            localizations.tapToAddFirst,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontSize: responsive.fs14,
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else // Display the list of recent transactions
                SliverToBoxAdapter(
                  child: Padding(
                    padding: responsive.padding(horizontal: 16),
                    child: Card(
                      child: Column(
                        children: List.generate(
                          transactionProvider.transactions.length > 3
                              ? 3
                              : transactionProvider.transactions.length,
                          (index) {
                            final transaction =
                                transactionProvider.transactions[index];
                            final isFirst = index == 0;
                            return Column(
                              children: [
                                if (!isFirst) Divider(indent: 70),
                                _buildTransactionRow(transaction, responsive),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

              SliverToBoxAdapter(child: SizedBox(height: responsive.sp24)),

              // Budgets preview: first two active budgets, worst-off first —
              // a real "over cap" preview backed by BudgetProvider.
              SliverToBoxAdapter(
                child: Padding(
                  padding: responsive.padding(horizontal: 16),
                  child: Consumer<BudgetProvider>(
                    builder: (context, budgetProvider, child) =>
                        _buildBudgetsPreview(context, budgetProvider, responsive),
                  ),
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: responsive.sp16)),

              // Goals preview: first two active goals, worst-off (lowest
              // progress) first — mirrors the Budgets preview above, backed
              // by GoalProvider's active goals.
              SliverToBoxAdapter(
                child: Padding(
                  padding: responsive.padding(horizontal: 16),
                  child: Consumer<GoalProvider>(
                    builder: (context, goalProvider, child) =>
                        _buildGoalsPreview(context, goalProvider, responsive),
                  ),
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: responsive.sp24)),

              // Quick links to the screens with no live preview data of
              // their own (Analytics, Reports) — navigation-only, so they
              // don't need a fetch the way Budgets/Goals do above.
              SliverToBoxAdapter(
                child: Padding(
                  padding: responsive.padding(horizontal: 16),
                  child: _buildQuickLinks(context, responsive),
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: responsive.sp24)),

              // AI Assistant teaser — "continue chatting" with the last
              // message when there's history (fetched cheaply above, no AI
              // call), otherwise a generic prompt into the chat.
              SliverToBoxAdapter(
                child: Padding(
                  padding: responsive.padding(horizontal: 16),
                  child: Consumer<ChatProvider>(
                    builder: (context, chatProvider, child) =>
                        _buildChatTeaser(context, authProvider, chatProvider, responsive),
                  ),
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: responsive.sp16)),

              // Insight teaser
              SliverToBoxAdapter(
                child: Padding(
                  padding: responsive.padding(horizontal: 16),
                  child: Consumer2<BudgetProvider, InsightProvider>(
                    builder: (context, budgetProvider, insightProvider, child) =>
                        _buildInsightTeaser(context, authProvider, budgetProvider, insightProvider, responsive),
                  ),
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: 100)), // Space for FAB
            ],
          ),
        ),
      ),
      // Floating Action Button to add new transactions
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToAddTransaction(),
        child: Icon(Icons.add_rounded),
        tooltip: localizations.addTransactionFabTooltip,
      ),
    );
  }

  // "Available to spend" hero with inflow/outflow stat tiles.
  Widget _buildHero(
    BuildContext context,
    AuthProvider authProvider,
    TransactionProvider transactionProvider,
    ResponsiveHelper responsive,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final balance = transactionProvider.balance;
    final currency = balance?.currency ?? authProvider.defaultCurrency;
    final symbol = currency.symbol;
    final available = balance?.availableBalance ?? 0.0;
    final total = balance?.balance ?? 0.0;
    final allocated = balance?.allocatedToGoals ?? 0.0;
    final inflow = balance?.totalInflow ?? 0.0;
    final outflow = balance?.totalOutflow ?? 0.0;

    final supporting = allocated > 0
        ? '$symbol${formatter.format(allocated)} set aside for goals · $symbol${formatter.format(total)} total'
        : '$symbol${formatter.format(total)} total';

    return HeroCard(
      label: 'Available to spend',
      value: '$symbol${formatter.format(available)}',
      supporting: supporting,
      labelTrailing: Container(
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currency.name.toUpperCase(),
              style: TextStyle(
                fontSize: responsive.fs12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            Icon(
              Icons.expand_more_rounded,
              size: responsive.icon16,
              color: scheme.onSurface,
            ),
          ],
        ),
      ),
      onLabelTap: _showMultiCurrencyBottomSheet,
      stats: [
        StatTile(
          icon: Icons.arrow_upward_rounded,
          label: AppLocalizations.of(context).inflow,
          value: '$symbol${formatter.format(inflow)}',
          iconColor: scheme.primary,
        ),
        StatTile(
          icon: Icons.arrow_downward_rounded,
          label: AppLocalizations.of(context).outflow,
          value: '$symbol${formatter.format(outflow)}',
          iconColor: scheme.error,
        ),
      ],
    );
  }

  // "Spending pace": last-7-days outflow bucketed by calendar day from the
  // real fetched transactions, rendered as a 7-bar chart (mockup lines
  // 97-116). No monthly comparison badge is shown — that would need a full
  // prior month of transactions and `_refreshData` only fetches a recent
  // page, so a "% under last month" figure would not be reliable.
  Widget _buildSpendingPace(
    BuildContext context,
    TransactionProvider transactionProvider,
    ResponsiveHelper responsive,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final days = List.generate(7, (i) => DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: 6 - i)));

    final totals = List<double>.filled(7, 0);
    for (final t in transactionProvider.transactions) {
      if (t.type != TransactionType.outflow) continue;
      final d = DateTime(t.date.year, t.date.month, t.date.day);
      final index = days.indexWhere((day) => day == d);
      if (index != -1) totals[index] += t.amount;
    }
    final maxTotal = totals.fold<double>(0, (max, v) => v > max ? v : max);

    return Card(
      child: Padding(
        padding: responsive.padding(left: 18, right: 18, top: 18, bottom: 16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spending pace',
            style: TextStyle(
              fontSize: responsive.fs16,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          SizedBox(height: responsive.sp16),
          SizedBox(
            height: 78,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final isToday = i == 6;
                final ratio = maxTotal > 0 ? (totals[i] / maxTotal) : 0.0;
                final barHeight = totals[i] > 0 ? (10 + ratio * 68) : 4.0;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: responsive.spacing(mobile: 2.5),
                    ),
                    child: Container(
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: isToday
                            ? scheme.primary
                            : scheme.secondaryContainer,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          SizedBox(height: responsive.sp8),
          Row(
            children: days
                .map(
                  (d) => Expanded(
                    child: Text(
                      DateFormat('E').format(d).substring(0, 1),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: responsive.fs11,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        ),
      ),
    );
  }

  // Budgets preview: the two active budgets closest to (or over) their cap,
  // linking to the full Budgets screen — mockup lines 118-136. Hidden
  // entirely when there are no active budgets, rather than showing an empty
  // or fabricated card.
  Widget _buildBudgetsPreview(
    BuildContext context,
    BudgetProvider budgetProvider,
    ResponsiveHelper responsive,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    final preview = [...budgetProvider.activeBudgets]
      ..sort((a, b) => b.percentageUsed.compareTo(a.percentageUsed));
    if (preview.isEmpty) return const SizedBox.shrink();
    final shown = preview.take(2).toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, '/budgets'),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: responsive.sp6),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: responsive.padding(left: 14, right: 14, top: 10, bottom: 6),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      localizations.budgets,
                      style: TextStyle(
                        fontSize: responsive.fs16,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: responsive.sp8),
                  Text(
                    localizations.seeMore,
                    style: TextStyle(
                      fontSize: responsive.fs13,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: responsive.icon18,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
            for (final budget in shown)
              Padding(
                padding: responsive.padding(left: 14, right: 14, top: 10, bottom: 10),
                child: _buildBudgetPreviewRow(context, budget, responsive),
              ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildBudgetPreviewRow(
    BuildContext context,
    Budget budget,
    ResponsiveHelper responsive,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final over = budget.percentageUsed > 100;
    final tint = over ? scheme.errorContainer : scheme.secondaryContainer;
    final ink = over ? scheme.error : scheme.primary;
    final daysRemaining = budget.endDate.difference(DateTime.now()).inDays;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Icon(
            iconForCategoryName(budget.name),
            size: responsive.iconSize(mobile: 22),
            color: ink,
          ),
        ),
        SizedBox(width: responsive.spacing(mobile: 14)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      budget.name,
                      style: TextStyle(
                        fontSize: responsive.fs14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: responsive.sp8),
                  Text(
                    '${budget.percentageUsed.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: responsive.fs13,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ],
              ),
              SizedBox(height: responsive.sp6),
              ProgressMeter(value: budget.percentageUsed / 100, overrideColor: ink),
              SizedBox(height: responsive.sp4),
              Text(
                '${budget.displayTotalSpent} of ${budget.displayTotalBudget}'
                '${daysRemaining >= 0 ? ' · $daysRemaining days remaining' : ''}',
                style: TextStyle(
                  fontSize: responsive.fs12,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGoalsPreview(
    BuildContext context,
    GoalProvider goalProvider,
    ResponsiveHelper responsive,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    final preview = [...goalProvider.activeGoals]
      ..sort((a, b) => a.progressPercentage.compareTo(b.progressPercentage));
    if (preview.isEmpty) return const SizedBox.shrink();
    final shown = preview.take(2).toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, '/goals'),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: responsive.sp6),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: responsive.padding(left: 14, right: 14, top: 10, bottom: 6),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      localizations.goals,
                      style: TextStyle(
                        fontSize: responsive.fs16,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: responsive.sp8),
                  Text(
                    localizations.seeMore,
                    style: TextStyle(
                      fontSize: responsive.fs13,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: responsive.icon18,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
            for (final goal in shown)
              Padding(
                padding: responsive.padding(left: 14, right: 14, top: 10, bottom: 10),
                child: _buildGoalPreviewRow(context, goal, responsive),
              ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoalPreviewRow(
    BuildContext context,
    Goal goal,
    ResponsiveHelper responsive,
  ) {
    final scheme = Theme.of(context).colorScheme;
    // Reads too dark against the tinted circle in dark mode, so this mirrors
    // goals_screen.dart's own _accentColor helper rather than plain primary.
    final accent = Theme.of(context).brightness == Brightness.dark ? scheme.secondary : scheme.primary;

    final IconData goalIcon;
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
          child: Icon(
            goalIcon,
            size: responsive.iconSize(mobile: 22),
            color: accent,
          ),
        ),
        SizedBox(width: responsive.spacing(mobile: 14)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      goal.name,
                      style: TextStyle(
                        fontSize: responsive.fs14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: responsive.sp8),
                  Text(
                    '${goal.progressPercentage.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: responsive.fs13,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ],
              ),
              SizedBox(height: responsive.sp6),
              ProgressMeter(value: goal.progressPercentage / 100, overrideColor: accent),
              SizedBox(height: responsive.sp4),
              Text(
                '${goal.displayCurrentAmount} of ${goal.displayTargetAmount}',
                style: TextStyle(
                  fontSize: responsive.fs12,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickLinks(BuildContext context, ResponsiveHelper responsive) {
    final localizations = AppLocalizations.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: responsive.spacing(mobile: 10), horizontal: responsive.sp6),
        child: Row(
          children: [
            Expanded(
              child: _buildQuickLinkTile(
                context,
                icon: Icons.trending_up_rounded,
                label: localizations.inflowAnalytics,
                onTap: () => Navigator.pushNamed(context, '/inflow-analytics'),
                responsive: responsive,
              ),
            ),
            Expanded(
              child: _buildQuickLinkTile(
                context,
                icon: Icons.pie_chart_rounded,
                label: localizations.outflowAnalytics,
                onTap: () => Navigator.pushNamed(context, '/outflow-analytics'),
                responsive: responsive,
              ),
            ),
            Expanded(
              child: _buildQuickLinkTile(
                context,
                icon: Icons.assessment_rounded,
                label: localizations.financialReports,
                onTap: () => Navigator.pushNamed(context, '/reports'),
                responsive: responsive,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickLinkTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required ResponsiveHelper responsive,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: responsive.padding(vertical: 8, horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: responsive.iconSize(mobile: 22), color: scheme.primary),
            ),
            SizedBox(height: responsive.sp6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: responsive.fs11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // Tonal callout, in priority order: (1) an insight already read this
  // session ("continue reading" — InsightProvider is never fetched from
  // here, only read, since fetching can trigger a real AI generation call
  // on the backend when nothing is cached yet), (2) a real, computed
  // observation when one exists (an over-cap budget, from data already
  // fetched for the Budgets preview above), (3) the generic AI-insights
  // teaser. The mockup's own example ("Food & Daily Living is 9% over its
  // cap with 22 days to go") is budget arithmetic, not an AI call, so (2)
  // doesn't require a premium request to show something real either.
  Widget _buildInsightTeaser(
    BuildContext context,
    AuthProvider authProvider,
    BudgetProvider budgetProvider,
    InsightProvider insightProvider,
    ResponsiveHelper responsive,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    final overCap = [...budgetProvider.activeBudgets]
      ..sort((a, b) => b.percentageUsed.compareTo(a.percentageUsed));
    final worst = overCap.isNotEmpty && overCap.first.percentageUsed > 100 ? overCap.first : null;
    final cachedInsight = insightProvider.insight;

    final String headline;
    final String body;
    final VoidCallback onTap;
    if (cachedInsight != null) {
      headline = 'Continue reading';
      body = _firstInsightLine(cachedInsight.content);
      onTap = () => Navigator.pushNamed(context, '/insights');
    } else if (worst != null) {
      final over = (worst.percentageUsed - 100).toStringAsFixed(0);
      final daysLeft = worst.endDate.difference(DateTime.now()).inDays;
      headline = daysLeft >= 0
          ? '${worst.name} is $over% over its cap with $daysLeft days to go.'
          : '${worst.name} is $over% over its cap.';
      body = 'Tap to see what to cut — and by how much.';
      onTap = () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BudgetDetailScreen(budget: worst)),
      );
    } else {
      headline = localizations.aiInsights;
      body = localizations.viewComprehensiveAnalysis;
      onTap = () => Navigator.pushNamed(context, '/insights');
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: responsive.padding(all: 18),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_rounded, size: responsive.icon20, color: scheme.tertiary),
                SizedBox(width: responsive.sp8),
                Flexible(
                  child: Text(
                    'Insight',
                    style: TextStyle(
                      fontSize: responsive.fs13,
                      fontWeight: FontWeight.w700,
                      color: scheme.tertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!authProvider.isPremium) ...[
                  Spacer(),
                  // Solid tertiary fill (not tertiaryContainer) — this card's
                  // own background already IS tertiaryContainer, so a
                  // same-tone badge would be invisible against it.
                  StatusPill(
                    label: localizations.premium.toUpperCase(),
                    background: scheme.tertiary,
                    foreground: scheme.onTertiary,
                    dense: true,
                  ),
                ],
              ],
            ),
            SizedBox(height: responsive.sp8),
            Text(
              headline,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: responsive.fontSize(mobile: 15),
                color: scheme.onTertiaryContainer,
              ),
            ),
            SizedBox(height: responsive.sp6),
            Text(
              body,
              style: TextStyle(
                fontSize: responsive.fs13,
                fontWeight: FontWeight.w500,
                color: scheme.onTertiaryContainer,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // Strips the leading markdown noise (headings, bullets) off an AI report
  // so a one-line "continue reading" preview doesn't start with a stray
  // "##" or "*". Mirrors insights_screen.dart's own _firstLine helper.
  String _firstInsightLine(String content) {
    final stripped = content.replaceAll(RegExp(r'^[#*\-\s]+', multiLine: true), '').trim();
    final idx = stripped.indexOf('\n');
    final firstBlock = idx == -1 ? stripped : stripped.substring(0, idx);
    return firstBlock.length > 120 ? '${firstBlock.substring(0, 120)}…' : firstBlock;
  }

  // Same tonal-callout treatment as the Insight teaser below, for the
  // Assistant — "continue chatting" with the last message when there's
  // history, otherwise a generic prompt into the chat. Chat history is
  // safe to prefetch unconditionally (just a GET, no AI generation), so
  // this doesn't need the "only read what's already cached" caveat that
  // applies to the Insight teaser.
  Widget _buildChatTeaser(
    BuildContext context,
    AuthProvider authProvider,
    ChatProvider chatProvider,
    ResponsiveHelper responsive,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    final lastMessage = chatProvider.messages.isNotEmpty ? chatProvider.messages.last : null;

    final String headline;
    final String body;
    if (lastMessage != null) {
      headline = 'Continue chatting';
      body = lastMessage.content;
    } else {
      headline = localizations.aiAssistant;
      body = 'Ask me anything about your finances.';
    }

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/ai-chat'),
      child: Container(
        width: double.infinity,
        padding: responsive.padding(all: 18),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.forum_rounded, size: responsive.icon20, color: scheme.tertiary),
                SizedBox(width: responsive.sp8),
                Flexible(
                  child: Text(
                    localizations.aiAssistant,
                    style: TextStyle(
                      fontSize: responsive.fs13,
                      fontWeight: FontWeight.w700,
                      color: scheme.tertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!authProvider.isPremium) ...[
                  Spacer(),
                  StatusPill(
                    label: 'TRY FREE',
                    background: scheme.tertiary,
                    foreground: scheme.onTertiary,
                    dense: true,
                  ),
                ],
              ],
            ),
            SizedBox(height: responsive.sp8),
            Text(
              headline,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: responsive.fontSize(mobile: 15),
                color: scheme.onTertiaryContainer,
              ),
            ),
            SizedBox(height: responsive.sp6),
            Text(
              body,
              style: TextStyle(
                fontSize: responsive.fs13,
                fontWeight: FontWeight.w500,
                color: scheme.onTertiaryContainer,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // Row for a single recent transaction — kept custom (rather than the
  // generic AppListRow) so the recurrence / auto-created / description
  // detail lines from the original design keep showing.
  Widget _buildTransactionRow(
    Transaction transaction,
    ResponsiveHelper responsive,
  ) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isInflow = transaction.type == TransactionType.inflow;
    final tint = isInflow ? scheme.primaryContainer : scheme.errorContainer;
    final ink = isInflow ? scheme.primary : scheme.error;
    // Per the component spec: outflow amounts stay neutral onSurface, only
    // inflow is coloured — the icon tint above still signals direction.
    final moneyColor = isInflow ? scheme.primary : scheme.onSurface;

    return InkWell(
      onTap: () => _navigateToEditTransaction(transaction),
      child: Padding(
        padding: responsive.padding(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(iconForCategoryName(transaction.mainCategory), color: ink),
            ),
            SizedBox(width: responsive.sp16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.subCategory,
                    style: TextStyle(
                      fontSize: responsive.fontSize(mobile: 15),
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (transaction.recurrence?.enabled ?? false) ...[
                    SizedBox(height: responsive.sp4),
                    Row(
                      children: [
                        Icon(
                          Icons.repeat_rounded,
                          size: responsive.icon16,
                          color: scheme.primary,
                        ),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            transaction.recurrence!.config!.getDisplayText(),
                            style: TextStyle(
                              fontSize: responsive.fs11,
                              color: scheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (transaction.parentTransactionId != null) ...[
                    SizedBox(height: responsive.sp4),
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: responsive.icon16,
                          color: scheme.tertiary,
                        ),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            localizations.autoCreated,
                            style: TextStyle(
                              fontSize: responsive.fs11,
                              color: scheme.tertiary,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  Text(
                    transaction.mainCategory,
                    style: TextStyle(
                      fontSize: responsive.fs12,
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (transaction.description != null &&
                      transaction.description!.isNotEmpty) ...[
                    SizedBox(height: 2),
                    Text(
                      transaction.description!,
                      style: TextStyle(
                        fontSize: responsive.fs12,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: responsive.sp8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: responsive.widthPercent(30)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isInflow ? '+' : '-'}${transaction.currency.symbol}${formatter.format(transaction.amount)}',
                    style: AppTheme.money(15, weight: FontWeight.w700, color: moneyColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    DateFormat('yyyy-MM-dd').format(transaction.date),
                    style: TextStyle(
                      fontSize: responsive.fs12,
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ADD this new method to show multi-currency bottom sheet
  void _showMultiCurrencyBottomSheet() async {
    final localizations = AppLocalizations.of(context);
    final responsive = ResponsiveHelper(context);

    // Fetch all balances
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    try {
      final multiBalances = await ApiService.getAllBalances();
      Navigator.pop(context); // Close loading dialog

      final defaultCurrency = Provider.of<AuthProvider>(
        context,
        listen: false,
      ).defaultCurrency;

      showAppBottomSheet<void>(
        context: context,
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.allCurrencyBalances,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: responsive.sp4),
              Text(
                'Each keeps its own balance — nothing is converted behind your back.',
                style: TextStyle(
                  fontSize: responsive.fs13,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              SizedBox(height: responsive.sp20),
              ...multiBalances.currencies.map((currency) {
                final balance = multiBalances.getBalanceForCurrency(currency);
                if (balance == null) return SizedBox.shrink();
                final isDefault = currency == defaultCurrency;
                final heldText = balance.allocatedToGoals > 0
                    ? '${currency.symbol}${formatter.format(balance.allocatedToGoals)} held for goals'
                    : 'Nothing held';

                return Container(
                  margin: EdgeInsets.only(bottom: responsive.sp16),
                  padding: responsive.padding(all: 18),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    currency.symbol,
                                    style: TextStyle(
                                      fontSize: responsive.fs14,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                SizedBox(width: responsive.sp12),
                                Flexible(
                                  child: Text(
                                    currency.displayName,
                                    style: TextStyle(
                                      fontSize: responsive.fontSize(mobile: 15),
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isDefault) ...[
                            SizedBox(width: responsive.sp8),
                            StatusPill(
                              label: localizations.defaultBalance.toUpperCase(),
                              background: scheme.secondaryContainer,
                              foreground: scheme.onPrimaryContainer,
                              dense: true,
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: responsive.sp4),
                      Padding(
                        padding: EdgeInsets.only(left: 44),
                        child: Text(
                          heldText,
                          style: TextStyle(
                            fontSize: responsive.fs12,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(height: responsive.sp16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              balance.displayBalance,
                              style: AppTheme.money(24, weight: FontWeight.w800, color: scheme.onSurface),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: responsive.sp6),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              currency.name.toUpperCase(),
                              style: TextStyle(
                                fontSize: responsive.fs11,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: responsive.sp8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                localizations.available,
                                style: TextStyle(
                                  fontSize: responsive.fs12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '${currency.symbol}${formatter.format(balance.availableBalance)}',
                                style: AppTheme.money(15, weight: FontWeight.w600, color: scheme.onSurface),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                localizations.allocatedToGoals,
                                style: TextStyle(
                                  fontSize: responsive.fs12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '${currency.symbol}${formatter.format(balance.allocatedToGoals)}',
                                style: AppTheme.money(
                                  15,
                                  weight: FontWeight.w600,
                                  color: scheme.tertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: responsive.sp12),
                      Divider(),
                      SizedBox(height: responsive.sp8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.arrow_upward_rounded,
                                size: responsive.icon16,
                                color: scheme.primary,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '${currency.symbol}${formatter.format(balance.totalInflow)}',
                                style: TextStyle(
                                  fontSize: responsive.fs13,
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(
                                Icons.arrow_downward_rounded,
                                size: responsive.icon16,
                                color: scheme.error,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '${currency.symbol}${formatter.format(balance.totalOutflow)}',
                                style: TextStyle(
                                  fontSize: responsive.fs13,
                                  color: scheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          );
        },
      );
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      final scheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load currency balances: ${e.toString().replaceAll('Exception: ', '')}',
            style: TextStyle(color: scheme.onErrorContainer),
          ),
          backgroundColor: scheme.errorContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Navigate to the AddTransactionScreen and handle results
  void _navigateToAddTransaction() {
    _showAddTransactionOptions();
  }

  void _showAddTransactionOptions() {
    final localizations = AppLocalizations.of(context);
    final responsive = ResponsiveHelper(context);

    showAppBottomSheet<void>(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.addTransaction,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: responsive.sp20),
            _buildAddOption(
              icon: Icons.edit_rounded,
              title: localizations.manualEntry,
              subtitle: localizations.typeTransactionDetails,
              isPremiumFeature: false,
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddTransactionScreen()),
                );
                if (result == true) {
                  _refreshData();
                  _showSuccessSnackBar(localizations.transactionAdded);
                }
              },
            ),
            SizedBox(height: responsive.sp12),
            _buildAddOption(
              icon: Icons.mic_rounded,
              title: localizations.voiceInput,
              subtitle: localizations.speakYourTransaction,
              isPremiumFeature: true,
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => VoiceInputScreen()),
                );
                if (result == true) {
                  _refreshData();
                  _showSuccessSnackBar(localizations.transactionAdded);
                }
              },
            ),
            SizedBox(height: responsive.sp12),
            _buildAddOption(
              icon: Icons.document_scanner_rounded,
              title: localizations.scanReceipt,
              subtitle: localizations.takeUploadPhoto,
              isPremiumFeature: true,
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ImageInputScreen()),
                );
                if (result == true) {
                  _refreshData();
                  _showSuccessSnackBar(localizations.transactionAdded);
                }
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildAddOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isPremiumFeature = false,
  }) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isLocked = isPremiumFeature && !authProvider.isPremium;
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: AppListRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        trailing: isLocked
            ? Padding(
                padding: const EdgeInsets.only(left: 8),
                child: StatusPill(
                  label: localizations.premium.toUpperCase(),
                  background: scheme.tertiaryContainer,
                  foreground: scheme.tertiary,
                  dense: true,
                ),
              )
            : Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
      ),
    );
  }

  // Uniform dark "snack" toast (mockup lines 2106-2111) — background, text
  // colour, shape and behaviour all come from the theme's SnackBarThemeData
  // (already brightness-aware), so nothing here is overridden per-call.
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppTheme.snackAccent, size: 20),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  // Navigate to the EditTransactionScreen and handle results
  void _navigateToEditTransaction(Transaction transaction) async {
    final localizations = AppLocalizations.of(context);
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditTransactionScreen(
          transaction: transaction,
        ), // Pass transaction data
      ),
    );

    if (result == true) {
      // Transaction updated
      _refreshData(); // Refresh data
      _showSuccessSnackBar(localizations.transactionUpdated);
    } else if (result == 'deleted') {
      // Transaction deleted
      _refreshData(); // Refresh data
      _showSuccessSnackBar(localizations.transactionDeleted);
    }
  }
}
