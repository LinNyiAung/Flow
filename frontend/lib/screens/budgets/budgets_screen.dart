import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/budget.dart';
import '../../providers/budget_provider.dart';
import '../../widgets/app_drawer.dart';
import 'create_budget_screen.dart';
import 'budget_detail_screen.dart';
import 'package:frontend/services/responsive_helper.dart';

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
    budgetProvider.fetchMultiCurrencySummary(),  // ADD this line
  ]);
}

  void _navigateToCreateBudget() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateBudgetScreen()),
    );
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);

    if (result == true) {
      _refreshData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localizations.budgetCreatedSuccessfully,
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Color(0xFF4CAF50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(8))),
          behavior: SnackBarBehavior.floating,
        ),
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
          SnackBar(
            content: Text(
              localizations.budgetDeletedSuccessfully,
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final budgetProvider = Provider.of<BudgetProvider>(context);
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(
          localizations.budgets,
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
          // Notification Icon with Badge
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
                        icon: Icon(
                          Icons.notifications_outlined,
                          color: Color(0xFF667eea),
                        ),
                        onPressed: () {
                          Navigator.pushNamed(context, '/notifications').then((
                            _,
                          ) {
                            // Refresh data when returning from notifications
                            notificationProvider.fetchUnreadCount();
                          });
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
            colors: [Color(0xFF667eea).withOpacity(0.1), Colors.white],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _refreshData,
          color: Color(0xFF667eea),
          child: CustomScrollView(
            slivers: [
              // Summary Card
              if (budgetProvider.multiCurrencySummary != null)
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
                                  localizations.budgetSummary,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: responsive.fs16,
                                  ),
                                ),
                                Icon(Icons.account_balance_wallet, color: Colors.white),
                              ],
                            ),
                            SizedBox(height: responsive.sp16),
                            
                            // Overall stats
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildSummaryItem(
                                  localizations.active,
                                  budgetProvider.multiCurrencySummary!.activeBudgets.toString(),
                                ),
                                Container(height: 40, width: 1, color: Colors.white.withOpacity(0.3)),
                                _buildSummaryItem(
                                  localizations.exceeded,
                                  budgetProvider.multiCurrencySummary!.exceededBudgets.toString(),
                                ),
                                Container(height: 40, width: 1, color: Colors.white.withOpacity(0.3)),
                                _buildSummaryItem(
                                  localizations.total,
                                  budgetProvider.multiCurrencySummary!.totalBudgets.toString(),
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
                            
                            ...budgetProvider.multiCurrencySummary!.currencySummaries.map((summary) {
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
                                          '${summary.activeBudgets} active',
                                          style: GoogleFonts.poppins(
                                            fontSize: responsive.fs11,
                                            color: Colors.white.withOpacity(0.7),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: responsive.sp8),
                                    Text(
                                      '${summary.displayTotalSpent} / ${summary.displayTotalAllocated}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: responsive.fs18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    LinearProgressIndicator(
                                      value: summary.percentageUsed / 100,
                                      backgroundColor: Colors.white.withOpacity(0.2),
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      minHeight: responsive.spacing(mobile: 6),
                                    ),
                                    SizedBox(height: responsive.sp4),
                                    Text(
                                      '${summary.percentageUsed.toStringAsFixed(1)}% Used',
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

              // NEW: Currency Filter Chips
              SliverToBoxAdapter(
                child: Padding(
                  padding: responsive.padding(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizations.currency,
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333),
                        ),
                      ),
                      SizedBox(height: responsive.sp8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // 'All' chip
                          ChoiceChip(
                            label: Text(
                              localizations.allCurrencies,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs12,
                                fontWeight: FontWeight.w500,
                                color: _selectedCurrency == null ? Colors.white : Color(0xFF667eea),
                              ),
                            ),
                            selected: _selectedCurrency == null,
                            onSelected: (selected) {
                              setState(() {
                                _selectedCurrency = null;
                              });
                              _refreshData();
                            },
                            selectedColor: Color(0xFF667eea),
                            backgroundColor: Colors.white,
                            padding: responsive.padding(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
                              side: BorderSide(color: Color(0xFF667eea), width: 1),
                            ),
                          ),
                          // Individual currency chips
                          ...Currency.values.map((currency) {
                            final isSelected = _selectedCurrency == currency;
                            return ChoiceChip(
                              label: Text(
                                '${currency.symbol} ${currency.displayName}',
                                style: GoogleFonts.poppins(
                                  fontSize: responsive.fs12,
                                  fontWeight: FontWeight.w500,
                                  color: isSelected ? Colors.white : Color(0xFF667eea),
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  _selectedCurrency = currency;
                                });
                                _refreshData();
                              },
                              selectedColor: Color(0xFF667eea),
                              backgroundColor: Colors.white,
                              padding: responsive.padding(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
                                side: BorderSide(color: Color(0xFF667eea), width: 1),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: responsive.sp16)),

              // Filter Toggle
              SliverToBoxAdapter(
                child: Padding(
                  padding: responsive.padding(horizontal: 20),
                  child: Row(
                    children: [
                      _buildFilterChip(localizations.active, true),
                      SizedBox(width: responsive.sp8),
                      _buildFilterChip(localizations.filterChipAll, false),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: responsive.sp16)),

              // Budgets List
              if (budgetProvider.isLoading)
                SliverToBoxAdapter(
                  child: Container(
                    height: responsive.cardHeight(baseHeight: 200),
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF667eea),
                        ),
                      ),
                    ),
                  ),
                )
              else if (budgetProvider.budgets.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyState())
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final budget = budgetProvider.budgets[index];
                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      child: _buildBudgetCard(budget),
                    );
                  }, childCount: budgetProvider.budgets.length),
                ),

              SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreateBudget,
        backgroundColor: Color(0xFF667eea),
        child: Icon(Icons.add, color: Colors.white, size: responsive.icon28),
        elevation: 8,
        tooltip: localizations.createNewBudget,
      ),
    );
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

  Widget _buildFilterChip(String label, bool activeOnly) {
    final responsive = ResponsiveHelper(context);
    final isSelected = _activeOnly == activeOnly;
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
          _activeOnly = activeOnly;
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

  Widget _buildBudgetCard(Budget budget) {
    Color statusColor;
    IconData statusIcon;
    String statusLabel;
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);

    // Determine status based on upcoming, exceeded, completed, or active
    if (budget.isUpcoming || budget.status == BudgetStatus.upcoming) {
      statusColor = Color(0xFF2196F3); // Blue for upcoming
      statusIcon = Icons.schedule;
      statusLabel = localizations.upcoming;
    } else {
      switch (budget.status) {
        case BudgetStatus.exceeded:
          statusColor = Color(0xFFFF5722);
          statusIcon = Icons.warning;
          statusLabel = localizations.exceededCap;
          break;
        case BudgetStatus.completed:
          statusColor = Colors.grey;
          statusIcon = Icons.check_circle;
          statusLabel = localizations.completed;
          break;
        default:
          statusColor = Color(0xFF4CAF50);
          statusIcon = Icons.trending_up;
          statusLabel = localizations.activeCap;
      }
    }

  return GestureDetector(
    onTap: () => _navigateToBudgetDetail(budget),
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
          left: BorderSide(color: statusColor.withOpacity(0.3), width: 3),
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
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  ),
                  child: Icon(statusIcon, color: statusColor),
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
                              budget.name,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                            ),
                            child: Text(
                              statusLabel,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs10,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            budget.period.name.toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs11,
                              color: Colors.grey[600],
                            ),
                          ),
                          // NEW: Show currency
                          SizedBox(width: responsive.sp8),
                          Container(
                            padding: responsive.padding(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(responsive.borderRadius(4)),
                            ),
                            child: Text(
                              budget.currency.symbol,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                        // NEW: Show auto-create indicator
                        if (budget.autoCreateEnabled) ...[
                          SizedBox(width: responsive.sp8),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Color(0xFF667eea).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(responsive.borderRadius(4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  budget.autoCreateWithAi
                                      ? Icons.auto_awesome
                                      : Icons.autorenew,
                                  size: 10,
                                  color: Color(0xFF667eea),
                                ),
                                SizedBox(width: 2),
                                Text(
                                  localizations.auto,
                                  style: GoogleFonts.poppins(
                                    fontSize: responsive.fs10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF667eea),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // NEW: Show if this was auto-created
                        if (budget.isAutoCreated) ...[
                          SizedBox(width: responsive.sp8),
                          Icon(
                            Icons.autorenew,
                            size: 12,
                            color: Colors.grey[600],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.sp16),

            // Show "Starts in X days" for upcoming budgets
            if (budget.isUpcoming) ...[
              Container(
                padding: responsive.padding(all: 8),
                decoration: BoxDecoration(
                  color: Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: responsive.icon16,
                      color: Color(0xFF2196F3),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Starts ${DateFormat('MMM dd, yyyy').format(budget.startDate)}',
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs12,
                        color: Color(0xFF2196F3),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    budget.displayTotalSpent,  // NEW: use display method
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs18,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  Text(
                    budget.displayTotalBudget,  // NEW: use display method
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              SizedBox(height: responsive.sp8),
              LinearProgressIndicator(
                value: budget.percentageUsed / 100,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                minHeight: responsive.spacing(mobile: 6),
              ),
              SizedBox(height: responsive.sp4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${budget.percentageUsed.toStringAsFixed(1)}% Used',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs11,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    '${DateFormat('MMM dd').format(budget.startDate)} - ${DateFormat('MMM dd, yyyy').format(budget.endDate)}',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs11,
                      color: Colors.grey[600],
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
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
              ),
              child: Icon(
                Icons.account_balance_wallet,
                size: 48,
                color: Colors.white,
              ),
            ),
            SizedBox(height: responsive.sp24),
            Text(
              localizations.noBudgetsYet,
              style: GoogleFonts.poppins(
                fontSize: responsive.fs18,
                color: Color(0xFF333333),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: responsive.sp8),
            Text(
              localizations.createYourFirstBudget,
              style: GoogleFonts.poppins(fontSize: responsive.fs14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
