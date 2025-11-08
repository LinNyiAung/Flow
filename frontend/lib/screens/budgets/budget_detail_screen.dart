import 'package:flutter/material.dart';
import 'package:frontend/screens/budgets/edit_budget_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/budget.dart';
import '../../providers/budget_provider.dart';

class BudgetDetailScreen extends StatefulWidget {
  final Budget budget;

  BudgetDetailScreen({required this.budget});

  @override
  _BudgetDetailScreenState createState() => _BudgetDetailScreenState();
}

class _BudgetDetailScreenState extends State<BudgetDetailScreen> {
  late Budget _budget;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _budget = widget.budget;
    _refreshBudget();
  }

  Future<void> _refreshBudget() async {
    setState(() => _isRefreshing = true);

    final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);
    final updatedBudget = await budgetProvider.getBudget(_budget.id);

    if (updatedBudget != null) {
      setState(() {
        _budget = updatedBudget;
      });
    }

    setState(() => _isRefreshing = false);
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Budget',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this budget? This action cannot be undone.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteBudget();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Delete',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBudget() async {
    final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);
    final success = await budgetProvider.deleteBudget(_budget.id);

    if (success) {
      Navigator.pop(context, 'deleted');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            budgetProvider.error ?? 'Failed to delete budget',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _calculateDaysRemaining() {
    final now = DateTime.now().toUtc();
    final startDate = _budget.startDate.toUtc();
    final endDate = _budget.endDate.toUtc();

    print('\n=== DAYS REMAINING CALCULATION ===');
    print('Current time (UTC): $now');
    print('Budget start (UTC): $startDate');
    print('Budget end (UTC): $endDate');

    // Budget hasn't started yet
    if (now.isBefore(startDate)) {
      final daysUntilStart = startDate.difference(now).inDays;
      print('Budget not started. Days until start: $daysUntilStart');
      return 'Starts in $daysUntilStart days';
    }

    // Budget has ended
    if (now.isAfter(endDate)) {
      final daysEnded = now.difference(endDate).inDays;
      print('Budget ended. Days since end: $daysEnded');
      return 'Ended $daysEnded days ago';
    }

    // Budget is active
    final daysRemaining = endDate.difference(now).inDays;
    print('Budget active. Days remaining: $daysRemaining');
    return '$daysRemaining days remaining';
  }

  String _getBudgetStatusLabel() {
    final now = DateTime.now().toUtc();
    final startDate = _budget.startDate.toUtc();
    final endDate = _budget.endDate.toUtc();

    if (now.isBefore(startDate)) {
      return 'Starts In';
    } else if (now.isAfter(endDate)) {
      return 'Ended';
    } else {
      return 'Days Remaining';
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
    switch (_budget.status) {
      case BudgetStatus.exceeded:
        return Color(0xFFFF5722);
      case BudgetStatus.completed:
        return Colors.grey;
      default:
        return Color(0xFF4CAF50);
    }
  }

  IconData _getStatusIcon() {
    switch (_budget.status) {
      case BudgetStatus.exceeded:
        return Icons.warning;
      case BudgetStatus.completed:
        return Icons.check_circle;
      default:
        return Icons.trending_up;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Budget Details',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Color(0xFF333333)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Color(0xFF667eea)),
            onPressed: _isRefreshing ? null : _refreshBudget,
          ),
          IconButton(
            icon: Icon(Icons.edit, color: Color(0xFF667eea)),
            onPressed: () => _navigateToEditBudget(),
          ),
          IconButton(
            icon: Icon(Icons.delete, color: Colors.red),
            onPressed: _showDeleteConfirmation,
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
          onRefresh: _refreshBudget,
          color: Color(0xFF667eea),
          child: ListView(
            padding: EdgeInsets.all(20),
            children: [
              // Budget Overview Card
              Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF667eea).withOpacity(0.3),
                      spreadRadius: 2,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _budget.name,
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _getStatusIcon(),
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 4),
                              Text(
                                _budget.status.name.toUpperCase(),
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      _budget.period.name.toUpperCase(),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                    if (_budget.description != null) ...[
                      SizedBox(height: 8),
                      Text(
                        _budget.description!,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                    SizedBox(height: 20),
                    Text(
                      '\$${_budget.totalSpent.toStringAsFixed(2)} / \$${_budget.totalBudget.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _budget.percentageUsed / 100,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      minHeight: 8,
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_budget.percentageUsed.toStringAsFixed(1)}% Used',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                        Text(
                          'Remaining: \$${_budget.remainingBudget.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Add this after the main budget overview card and before "Budget Period Info"
              if (DateTime.now().toUtc().isBefore(
                _budget.startDate.toUtc(),
              )) ...[
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, color: Colors.blue[700], size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This budget will start on ${DateFormat('MMMM dd, yyyy').format(_budget.startDate)}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.blue[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (!_budget.isActive &&
                  DateTime.now().toUtc().isAfter(_budget.endDate.toUtc())) ...[
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.grey[600],
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This budget ended on ${DateFormat('MMMM dd, yyyy').format(_budget.endDate)}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: 24),

              // Budget Period Info
              Container(
                padding: EdgeInsets.all(16),
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
                child: Column(
                  children: [
                    _buildInfoRow(
                      Icons.calendar_today,
                      'Start Date',
                      DateFormat('MMMM dd, yyyy').format(_budget.startDate),
                    ),
                    Divider(height: 24),
                    _buildInfoRow(
                      Icons.event,
                      'End Date',
                      DateFormat('MMMM dd, yyyy').format(_budget.endDate),
                    ),
                    Divider(height: 24),
                    _buildInfoRow(
                      Icons.timelapse,
                      _getBudgetStatusLabel(),
                      _calculateDaysRemaining(),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Category Budgets
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Category Budgets',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                  Text(
                    '${_budget.categoryBudgets.length} categories',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),

              SizedBox(height: 12),

              ..._budget.categoryBudgets.map((catBudget) {
                return _buildCategoryCard(catBudget);
              }).toList(),

              SizedBox(height: 24),

              // Budget Tips
              if (_budget.status == BudgetStatus.exceeded)
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red[700]),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Budget Exceeded',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.red[900],
                              ),
                            ),
                            Text(
                              'You\'ve spent more than your allocated budget. Consider reducing spending in exceeded categories.',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.red[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else if (_budget.percentageUsed > 80)
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange[700]),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Approaching Budget Limit',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange[900],
                              ),
                            ),
                            Text(
                              'You\'ve used ${_budget.percentageUsed.toStringAsFixed(1)}% of your budget. Track your spending carefully.',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.orange[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Color(0xFF667eea), size: 20),
        SizedBox(width: 12),
        Text(
          '$label:',
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
        ),
        Spacer(),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(CategoryBudget catBudget) {
    final statusColor = catBudget.isExceeded
        ? Color(0xFFFF5722)
        : catBudget.percentageUsed > 80
        ? Color(0xFFFF9800)
        : Color(0xFF4CAF50);

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(16),
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
        border: Border(
          left: BorderSide(color: statusColor.withOpacity(0.3), width: 3),
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
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.category, color: statusColor, size: 18),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        catBudget.mainCategory,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (catBudget.isExceeded)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'EXCEEDED',
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.red[700],
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '\$${catBudget.spentAmount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
              Text(
                '\$${catBudget.allocatedAmount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          LinearProgressIndicator(
            value: catBudget.percentageUsed / 100,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            minHeight: 6,
          ),
          SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${catBudget.percentageUsed.toStringAsFixed(1)}% Used',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                'Remaining: \$${(catBudget.allocatedAmount - catBudget.spentAmount).toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
