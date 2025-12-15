import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/goal.dart';
import '../../providers/goal_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/app_drawer.dart';
import 'add_goal_screen.dart';
import 'goal_detail_screen.dart';
import 'package:frontend/services/responsive_helper.dart';

class GoalsScreen extends StatefulWidget {
  @override
  _GoalsScreenState createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  GoalStatus? _filterStatus;
  Currency _selectedCurrency = Currency.usd;

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
    goalProvider.fetchGoals(statusFilter: _filterStatus),
    goalProvider.fetchMultiCurrencySummary(),  // CHANGED from fetchSummary
    transactionProvider.fetchBalance(currency: _selectedCurrency),  // ADD currency parameter
  ]);
}

  void _navigateToAddGoal() async {
    final localizations = AppLocalizations.of(context);
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddGoalScreen()),
    );
    final responsive = ResponsiveHelper(context);

    if (result == true) {
      _refreshData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.goalCreatedSuccessfully, style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: Color(0xFF4CAF50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(8))),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.goalDeletedSuccessfully, style: GoogleFonts.poppins(color: Colors.white)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final goalProvider = Provider.of<GoalProvider>(context);
    final transactionProvider = Provider.of<TransactionProvider>(context);
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,  
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(
          localizations.financialGoals,
          style: GoogleFonts.poppins(
            fontSize: responsive.fs20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.menu),
          color: Color(0xFF333333),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
actions: [
  Padding(
    padding: responsive.padding(right: 16),
    child: Consumer<NotificationProvider>(
      builder: (context, notificationProvider, child) {
        return Stack(
          children: [
            Container(
              padding: responsive.padding(all: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 4,
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(Icons.notifications_outlined, color: Color(0xFF667eea)),
                onPressed: () {
                  Navigator.pushNamed(context, '/notifications');
                },
              ),
            ),
            if (notificationProvider.unreadCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: responsive.padding(all: 4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: BoxConstraints(
                    minWidth: responsive.spacing(mobile: 20),
                    minHeight: responsive.spacing(mobile: 20),
                  ),
                  child: Text(
                    '${notificationProvider.unreadCount > 9 ? '9+' : notificationProvider.unreadCount}',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: responsive.fs10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    ),
  ),
],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF667eea).withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _refreshData,
          color: Color(0xFF667eea),
          child: CustomScrollView(
            slivers: [
              // Summary Card
              if (goalProvider.multiCurrencySummary != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: responsive.padding(all: 20),
                    child: Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(20))),
                      elevation: 8,
                      child: Container(
                        padding: responsive.padding(all: 24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                          ),
                          borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  localizations.goalsSummary,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: responsive.fs16,
                                  ),
                                ),
                                Icon(Icons.flag, color: Colors.white),
                              ],
                            ),
                            SizedBox(height: responsive.sp16),
                            
                            // Overall stats
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildSummaryItem(
                                  localizations.active,
                                  goalProvider.multiCurrencySummary!.activeGoals.toString(),
                                ),
                                Container(height: 40, width: 1, color: Colors.white.withOpacity(0.3)),
                                _buildSummaryItem(
                                  localizations.achieved,
                                  goalProvider.multiCurrencySummary!.achievedGoals.toString(),
                                ),
                                Container(height: 40, width: 1, color: Colors.white.withOpacity(0.3)),
                                _buildSummaryItem(
                                  localizations.total,
                                  goalProvider.multiCurrencySummary!.totalGoals.toString(),
                                ),
                              ],
                            ),
                            
                            SizedBox(height: responsive.sp20),
                            Divider(color: Colors.white.withOpacity(0.3), height: 1),
                            SizedBox(height: responsive.sp16),
                            
                            // Per-currency breakdown
                            Text(
                              localizations.byCurrency,
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: responsive.fs14,
                              ),
                            ),
                            SizedBox(height: responsive.sp12),
                            
                            ...goalProvider.multiCurrencySummary!.currencySummaries.map((summary) {
                              return Container(
                                margin: EdgeInsets.only(bottom: 12),
                                padding: responsive.padding(all: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: responsive.padding(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(responsive.borderRadius(6)),
                                              ),
                                              child: Text(
                                                summary.currency.name.toUpperCase(),
                                                style: GoogleFonts.poppins(
                                                  fontSize: responsive.fs12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: responsive.sp8),
                                            Text(
                                              summary.currency.displayName,
                                              style: GoogleFonts.poppins(
                                                fontSize: responsive.fs12,
                                                color: Colors.white.withOpacity(0.9),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '${summary.activeGoals} active',
                                          style: GoogleFonts.poppins(
                                            fontSize: responsive.fs11,
                                            color: Colors.white.withOpacity(0.7),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: responsive.sp8),
                                    Text(
                                      '${summary.displayTotalAllocated} / ${summary.displayTotalTarget}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: responsive.fs18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    LinearProgressIndicator(
                                      value: summary.overallProgress / 100,
                                      backgroundColor: Colors.white.withOpacity(0.2),
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      minHeight: responsive.spacing(mobile: 6),
                                    ),
                                    SizedBox(height: responsive.sp4),
                                    Text(
                                      '${summary.overallProgress.toStringAsFixed(1)}% Complete',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: responsive.fs11,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Available Balance Card
              if (transactionProvider.balance != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: responsive.padding(horizontal: 20),
                    child: Column(
                      children: [
                        // Primary currency balance
                        Container(
                          padding: responsive.padding(all: 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                spreadRadius: 2,
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          localizations.availableBalance,
                                          style: GoogleFonts.poppins(
                                            fontSize: responsive.fs14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        SizedBox(height: responsive.sp4),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _selectedCurrency.displayName,
                                                style: GoogleFonts.poppins(
                                                  fontSize: responsive.fs12,
                                                  color: Colors.grey[500],
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: responsive.sp4),
                                            Container(
                                              padding: responsive.padding(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Color(0xFF667eea).withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(responsive.borderRadius(4)),
                                              ),
                                              child: Text(
                                                _selectedCurrency.name.toUpperCase(),
                                                style: GoogleFonts.poppins(
                                                  fontSize: responsive.fs10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF667eea),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        transactionProvider.balance != null &&
                                                transactionProvider.balance!.currency == _selectedCurrency
                                            ? '${_selectedCurrency.symbol}${transactionProvider.balance!.availableBalance.toStringAsFixed(2)}'
                                            : '${_selectedCurrency.symbol}0.00',
                                        style: GoogleFonts.poppins(
                                          fontSize: responsive.fs20,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF667eea),
                                        ),
                                      ),
                                      Text(
                                        localizations.forGoals,
                                        style: GoogleFonts.poppins(
                                          fontSize: responsive.fs11,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              SizedBox(height: responsive.sp12),
                              
                              // Expand button to view all currencies
                              GestureDetector(
                                onTap: () => _showAllCurrencyBalancesBottomSheet(),
                                child: Container(
                                  padding: responsive.padding(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.currency_exchange, size: responsive.icon16, color: Color(0xFF667eea)),
                                      SizedBox(width: responsive.sp8),
                                      Text(
                                        localizations.viewAllCurrencies,
                                        style: GoogleFonts.poppins(
                                          fontSize: responsive.fs13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF667eea),
                                        ),
                                      ),
                                      SizedBox(width: responsive.sp4),
                                      Icon(Icons.keyboard_arrow_down, size: responsive.icon16, color: Color(0xFF667eea)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              SliverToBoxAdapter(child: SizedBox(height: responsive.sp20)),

              // Filter Chips
              SliverToBoxAdapter(
                child: Padding(
                  padding: responsive.padding(horizontal: 20),
                  child: Row(
                    children: [
                      _buildFilterChip(localizations.filterChipAll, null),
                      SizedBox(width: responsive.sp8),
                      _buildFilterChip(localizations.active, GoalStatus.active),
                      SizedBox(width: responsive.sp8),
                      _buildFilterChip(localizations.achieved, GoalStatus.achieved),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: responsive.sp16)),

              // Goals List
              if (goalProvider.isLoading)
                SliverToBoxAdapter(
                  child: Container(
                    height: responsive.cardHeight(baseHeight: 200),
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                      ),
                    ),
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
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        child: _buildGoalCard(goal),
                      );
                    },
                    childCount: goalProvider.goals.length,
                  ),
                ),

              SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddGoal,
        backgroundColor: Color(0xFF667eea),
        child: Icon(Icons.add, color: Colors.white, size: responsive.icon28),
        elevation: 8,
        tooltip: localizations.createNewGoal,
      ),
    );
  }


  void _showAllCurrencyBalancesBottomSheet() async {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
      ),
    ),
  );

  try {
    final multiBalances = await ApiService.getAllBalances();
    Navigator.pop(context); // Close loading dialog

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: responsive.padding(all: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: responsive.padding(all: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    ),
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  ),
                  child: Icon(Icons.currency_exchange, color: Colors.white, size: responsive.icon20),
                ),
                SizedBox(width: responsive.sp12),
                Text(
                  localizations.allCurrencyBalances,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                ),
              ],
            ),
            SizedBox(height: responsive.sp24),

            ...multiBalances.currencies.map((currency) {
              final balance = multiBalances.getBalanceForCurrency(currency);
              if (balance == null) return SizedBox.shrink();

              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedCurrency = currency;
                  });
                  _refreshData();
                },
                child: Container(
                  margin: responsive.padding(bottom: 16),
                  padding: responsive.padding(all: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF667eea).withOpacity(0.1),
                        Color(0xFF764ba2).withOpacity(0.1)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                    border: Border.all(
                      color: _selectedCurrency == currency
                          ? Color(0xFF667eea)
                          : Color(0xFF667eea).withOpacity(0.3),
                      width: _selectedCurrency == currency ? 2 : 1,
                    ),
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
                                  padding: responsive.padding(all: 8),
                                  decoration: BoxDecoration(
                                    color: Color(0xFF667eea),
                                    borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                                  ),
                                  child: Text(
                                    currency.symbol,
                                    style: GoogleFonts.poppins(
                                      fontSize: responsive.fs18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                SizedBox(width: responsive.sp12),
                                Expanded(
                                  child: Text(
                                    currency.displayName,
                                    style: GoogleFonts.poppins(
                                      fontSize: responsive.fs16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF333333),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_selectedCurrency == currency)
                            Container(
                              padding: responsive.padding(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Color(0xFF4CAF50),
                                borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                              ),
                              child: Text(
                                localizations.selected,
                                style: GoogleFonts.poppins(
                                  fontSize: responsive.fs11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: responsive.sp16),
                      Text(
                        localizations.availableForGoals,
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs12,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: responsive.sp4),
                      Text(
                        '${currency.symbol}${balance.availableBalance.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF333333),
                        ),
                      ),
                      SizedBox(height: responsive.sp12),
                      Divider(),
                      SizedBox(height: responsive.sp8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                localizations.totalBalance,
                                style: GoogleFonts.poppins(
                                  fontSize: responsive.fs11,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                balance.displayBalance,
                                style: GoogleFonts.poppins(
                                  fontSize: responsive.fs14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF333333),
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                localizations.allocatedToGoals,
                                style: GoogleFonts.poppins(
                                  fontSize: responsive.fs11,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                '${currency.symbol}${balance.allocatedToGoals.toStringAsFixed(2)}',
                                style: GoogleFonts.poppins(
                                  fontSize: responsive.fs14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFFF9800),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),

            SizedBox(height: responsive.sp16),
          ],
        ),
      ),
    );
  } catch (e) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Failed to load balances: ${e.toString().replaceAll('Exception: ', '')}',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

  Widget _buildSummaryItem(String label, String value) {
    final responsive = ResponsiveHelper(context);
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: responsive.fs24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: Colors.white.withOpacity(0.8),
            fontSize: responsive.fs12,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, GoalStatus? status) {
    final isSelected = _filterStatus == status;
    final responsive = ResponsiveHelper(context);
    return ChoiceChip(
      label: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: responsive.fs13,
          fontWeight: FontWeight.w500,
          color: isSelected ? Colors.white : Color(0xFF667eea),
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterStatus = status;
        });
        _refreshData();
      },
      selectedColor: Color(0xFF667eea),
      backgroundColor: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
        side: BorderSide(color: Color(0xFF667eea), width: 1),
      ),
    );
  }

  Widget _buildGoalCard(Goal goal) {
  IconData goalIcon;
  Color goalColor;
  final responsive = ResponsiveHelper(context);
  final localizations = AppLocalizations.of(context);

  switch (goal.goalType) {
    case GoalType.savings:
      goalIcon = Icons.savings;
      goalColor = Color(0xFF4CAF50);
      break;
    case GoalType.debt_reduction:
      goalIcon = Icons.money_off;
      goalColor = Color(0xFFFF5722);
      break;
    case GoalType.large_purchase:
      goalIcon = Icons.shopping_bag;
      goalColor = Color(0xFF2196F3);
      break;
  }

  return GestureDetector(
    onTap: () => _navigateToGoalDetail(goal),
    child: Container(
      padding: responsive.padding(all: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            spreadRadius: 1,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
        border: Border(
          left: BorderSide(
            color: goalColor.withOpacity(0.3),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: responsive.icon48,
                height: responsive.icon48,
                decoration: BoxDecoration(
                  color: goalColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                ),
                child: Icon(goalIcon, color: goalColor),
              ),
              SizedBox(width: responsive.sp16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            goal.name,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333),
                            ),
                          ),
                        ),
                        if (goal.status == GoalStatus.achieved)
                          Container(
                            padding: responsive.padding(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Color(0xFF4CAF50).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                            ),
                            child: Text(
                              localizations.achieved,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4CAF50),
                              ),
                            ),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          goal.goalType.name.replaceAll('_', ' ').toUpperCase(),
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs11,
                            color: Colors.grey[600],
                          ),
                        ),
                        // ADD currency badge
                        SizedBox(width: responsive.sp8),
                        Container(
                          padding: responsive.padding(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: goalColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(responsive.borderRadius(4)),
                          ),
                          child: Text(
                            goal.currency.name.toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs10,
                              fontWeight: FontWeight.w600,
                              color: goalColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.sp16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  goal.displayCurrentAmount,  // UPDATED
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs18,
                    fontWeight: FontWeight.bold,
                    color: goalColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: responsive.sp8),
              Text(
                goal.displayTargetAmount,  // UPDATED
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.sp8),
          LinearProgressIndicator(
            value: goal.progressPercentage / 100,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(goalColor),
            minHeight: responsive.spacing(mobile: 6),
          ),
          SizedBox(height: responsive.sp4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${goal.progressPercentage.toStringAsFixed(1)}% Complete',
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs11,
                  color: Colors.grey[600],
                ),
              ),
              if (goal.targetDate != null)
                Text(
                  'Due ${DateFormat('MMM dd, yyyy').format(goal.targetDate!)}',
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs11,
                    color: Colors.grey[600],
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

  Widget _buildEmptyState() {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    return Center(
      child: Container(
        padding: responsive.padding(all: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: responsive.padding(all: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
              ),
              child: Icon(Icons.flag, size: responsive.icon48, color: Colors.white),
            ),
            SizedBox(height: responsive.sp24),
            Text(
              localizations.noGoalsYet,
              style: GoogleFonts.poppins(
                fontSize: responsive.fs18,
                color: Color(0xFF333333),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: responsive.sp8),
            Text(
              localizations.createGoalGetStarted,
              style: GoogleFonts.poppins(
                fontSize: responsive.fs14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}