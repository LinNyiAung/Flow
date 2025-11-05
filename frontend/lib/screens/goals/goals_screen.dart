import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/goal.dart';
import '../../providers/goal_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/app_drawer.dart';
import 'add_goal_screen.dart';
import 'goal_detail_screen.dart';

class GoalsScreen extends StatefulWidget {
  @override
  _GoalsScreenState createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  GoalStatus? _filterStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }

  Future<void> _refreshData() async {
    final goalProvider = Provider.of<GoalProvider>(context, listen: false);
    final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
    await Future.wait([
      goalProvider.fetchGoals(statusFilter: _filterStatus),
      goalProvider.fetchSummary(),
      transactionProvider.fetchBalance(),
    ]);
  }

  void _navigateToAddGoal() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddGoalScreen()),
    );

    if (result == true) {
      _refreshData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Goal created successfully!', style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: Color(0xFF4CAF50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _navigateToGoalDetail(Goal goal) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GoalDetailScreen(goal: goal)),
    );

    if (result != null) {
      _refreshData();
      if (result == 'deleted') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Goal deleted successfully!', style: GoogleFonts.poppins(color: Colors.white)),
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

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,  
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(
          'Financial Goals',
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Icon(Icons.notifications_outlined, color: Color(0xFF667eea)),
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
              if (goalProvider.summary != null)
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
                                  'Goals Summary',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 16,
                                  ),
                                ),
                                Icon(Icons.flag, color: Colors.white),
                              ],
                            ),
                            SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildSummaryItem('Active', goalProvider.summary!.activeGoals.toString()),
                                Container(height: 40, width: 1, color: Colors.white.withOpacity(0.3)),
                                _buildSummaryItem('Achieved', goalProvider.summary!.achievedGoals.toString()),
                                Container(height: 40, width: 1, color: Colors.white.withOpacity(0.3)),
                                _buildSummaryItem('Total', goalProvider.summary!.totalGoals.toString()),
                              ],
                            ),
                            SizedBox(height: 16),
                            Text(
                              '\$${goalProvider.summary!.totalAllocated.toStringAsFixed(2)} / \$${goalProvider.summary!.totalTarget.toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: goalProvider.summary!.overallProgress / 100,
                              backgroundColor: Colors.white.withOpacity(0.3),
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              minHeight: 8,
                            ),
                            SizedBox(height: 4),
                            Text(
                              '${goalProvider.summary!.overallProgress.toStringAsFixed(1)}% Complete',
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

              // Available Balance Card
              if (transactionProvider.balance != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 2,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Available Balance',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                '\$${transactionProvider.balance!.availableBalance.toStringAsFixed(2)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF667eea),
                                ),
                              ),
                            ],
                          ),
                          Icon(Icons.account_balance_wallet, color: Color(0xFF667eea), size: 32),
                        ],
                      ),
                    ),
                  ),
                ),

              SliverToBoxAdapter(child: SizedBox(height: 20)),

              // Filter Chips
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _buildFilterChip('All', null),
                      SizedBox(width: 8),
                      _buildFilterChip('Active', GoalStatus.active),
                      SizedBox(width: 8),
                      _buildFilterChip('Achieved', GoalStatus.achieved),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Goals List
              if (goalProvider.isLoading)
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
        child: Icon(Icons.add, color: Colors.white, size: 28),
        elevation: 8,
        tooltip: 'Create New Goal',
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

  Widget _buildFilterChip(String label, GoalStatus? status) {
    final isSelected = _filterStatus == status;
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
          _filterStatus = status;
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

  Widget _buildGoalCard(Goal goal) {
    IconData goalIcon;
    Color goalColor;

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
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: goalColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(goalIcon, color: goalColor),
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
                              goal.name,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                          if (goal.status == GoalStatus.achieved)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Color(0xFF4CAF50).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Achieved',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF4CAF50),
                                ),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        goal.goalType.name.replaceAll('_', ' ').toUpperCase(),
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
                Flexible(
                  child: Text(
                    '\$${goal.currentAmount.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: goalColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '\$${goal.targetAmount.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            LinearProgressIndicator(
              value: goal.progressPercentage / 100,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(goalColor),
              minHeight: 6,
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${goal.progressPercentage.toStringAsFixed(1)}% Complete',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
                if (goal.targetDate != null)
                  Text(
                    'Due ${DateFormat('MMM dd, yyyy').format(goal.targetDate!)}',
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
              child: Icon(Icons.flag, size: 48, color: Colors.white),
            ),
            SizedBox(height: 24),
            Text(
              'No goals yet',
              style: GoogleFonts.poppins(
                fontSize: 18,
                color: Color(0xFF333333),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Create your first financial goal to get started!',
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