import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }

  Future<void> _refreshData() async {
    final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);
    await Future.wait([
      budgetProvider.fetchBudgets(activeOnly: _activeOnly),
      budgetProvider.fetchSummary(),
    ]);
  }

  void _navigateToCreateBudget() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateBudgetScreen()),
    );

    if (result == true) {
      _refreshData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Budget created successfully!', style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: Color(0xFF4CAF50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

    if (result != null) {
      _refreshData();
      if (result == 'deleted') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Budget deleted successfully!', style: GoogleFonts.poppins(color: Colors.white)),
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

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(
          'Budgets',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.menu),
          color: Color(0xFF333333),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
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
              if (budgetProvider.summary != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 8,
                      child: Container(
                        padding: EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Budget Summary',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 16,
                                  ),
                                ),
                                Icon(Icons.account_balance_wallet, color: Colors.white),
                              ],
                            ),
                            SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildSummaryItem('Active', budgetProvider.summary!.activeBudgets.toString()),
                                Container(height: 40, width: 1, color: Colors.white.withOpacity(0.3)),
                                _buildSummaryItem('Exceeded', budgetProvider.summary!.exceededBudgets.toString()),
                                Container(height: 40, width: 1, color: Colors.white.withOpacity(0.3)),
                                _buildSummaryItem('Total', budgetProvider.summary!.totalBudgets.toString()),
                              ],
                            ),
                            SizedBox(height: 16),
                            Text(
                              '\$${budgetProvider.summary!.totalSpent.toStringAsFixed(2)} / \$${budgetProvider.summary!.totalAllocated.toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: budgetProvider.summary!.totalAllocated > 0
                                  ? budgetProvider.summary!.totalSpent / budgetProvider.summary!.totalAllocated
                                  : 0,
                              backgroundColor: Colors.white.withOpacity(0.3),
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              minHeight: 8,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Remaining: \$${budgetProvider.summary!.overallRemaining.toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Filter Toggle
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _buildFilterChip('Active', true),
                      SizedBox(width: 8),
                      _buildFilterChip('All', false),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Budgets List
              if (budgetProvider.isLoading)
                SliverToBoxAdapter(
                  child: Container(
                    height: 200,
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                      ),
                    ),
                  ),
                )
              else if (budgetProvider.budgets.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyState())
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final budget = budgetProvider.budgets[index];
                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        child: _buildBudgetCard(budget),
                      );
                    },
                    childCount: budgetProvider.budgets.length,
                  ),
                ),

              SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreateBudget,
        backgroundColor: Color(0xFF667eea),
        child: Icon(Icons.add, color: Colors.white, size: 28),
        elevation: 8,
        tooltip: 'Create New Budget',
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, bool activeOnly) {
    final isSelected = _activeOnly == activeOnly;
    return ChoiceChip(
      label: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 13,
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
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Color(0xFF667eea), width: 1),
      ),
    );
  }

  Widget _buildBudgetCard(Budget budget) {
    Color statusColor;
    IconData statusIcon;

    switch (budget.status) {
      case BudgetStatus.exceeded:
        statusColor = Color(0xFFFF5722);
        statusIcon = Icons.warning;
        break;
      case BudgetStatus.completed:
        statusColor = Colors.grey;
        statusIcon = Icons.check_circle;
        break;
      default:
        statusColor = Color(0xFF4CAF50);
        statusIcon = Icons.trending_up;
    }

    return GestureDetector(
      onTap: () => _navigateToBudgetDetail(budget),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
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
              color: statusColor.withOpacity(0.3),
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
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(statusIcon, color: statusColor),
                ),
                SizedBox(width: 16),
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
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              budget.status.name.toUpperCase(),
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        budget.period.name.toUpperCase(),
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '\$${budget.totalSpent.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                Text(
                  '\$${budget.totalBudget.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            LinearProgressIndicator(
              value: budget.percentageUsed / 100,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 6,
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${budget.percentageUsed.toStringAsFixed(1)}% Used',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  '${DateFormat('MMM dd').format(budget.startDate)} - ${DateFormat('MMM dd, yyyy').format(budget.endDate)}',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
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
    return Center(
      child: Container(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.account_balance_wallet, size: 48, color: Colors.white),
            ),
            SizedBox(height: 24),
            Text(
              'No budgets yet',
              style: GoogleFonts.poppins(
                fontSize: 18,
                color: Color(0xFF333333),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Create your first budget to track spending!',
              style: GoogleFonts.poppins(
                fontSize: 14,
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