import 'package:flutter/material.dart';
import 'package:frontend/screens/budgets/edit_budget_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/budget.dart';
import '../../providers/budget_provider.dart';
import 'package:frontend/services/responsive_helper.dart';

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
    final updatedBudget = await budgetProvider.getBudget(_budget.id);

    if (updatedBudget != null) {
      setState(() {
        _budget = updatedBudget;
      });
    }

    setState(() => _isRefreshing = false);
  }

  void _showDeleteConfirmation() {
  final responsive = ResponsiveHelper(context);
  final localizations = AppLocalizations.of(context);
  showDialog(
    context: context,
    barrierDismissible: !_isDeleting,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
          ),
          title: Text(
            localizations.deleteBudget,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          content: Text(
            localizations.deleteBudgetAlert,
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: _isDeleting ? null : () => Navigator.pop(context),
              child: Text(
                localizations.dialogCancel,
                style: GoogleFonts.poppins(
                  color: _isDeleting ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
            ElevatedButton(
              onPressed: _isDeleting
                  ? null
                  : () async {
                      setDialogState(() {
                        _isDeleting = true;
                      });
                      setState(() {
                        _isDeleting = true;
                      });
                      
                      await _deleteBudget();
                      
                      if (mounted) {
                        setState(() {
                          _isDeleting = false;
                        });
                      }
                      
                      Navigator.pop(context);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                ),
              ),
              child: _isDeleting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      localizations.delete,
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
            ),
          ],
        );
      },
    ),
  );
}

  Future<void> _deleteBudget() async {
    final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);
    final success = await budgetProvider.deleteBudget(_budget.id);
    final localizations = AppLocalizations.of(context);

    if (success) {
      Navigator.pop(context, localizations.deleted);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            budgetProvider.error ?? localizations.failedToDeleteBudget,
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

    // Budget hasn't started yet
    if (now.isBefore(startDate)) {
      final daysUntilStart = startDate.difference(now).inDays;

      return 'Starts in $daysUntilStart days';
    }

    // Budget has ended
    if (now.isAfter(endDate)) {
      final daysEnded = now.difference(endDate).inDays;

      return 'Ended $daysEnded days ago';
    }

    // Budget is active
    final daysRemaining = endDate.difference(now).inDays;

    return '$daysRemaining days remaining';
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
      return Color(0xFF2196F3); // Blue for upcoming
    }

    switch (_budget.status) {
      case BudgetStatus.exceeded:
        return Color(0xFFFF5722);
      case BudgetStatus.completed:
        return Colors.grey;
      case BudgetStatus.upcoming:
        return Color(0xFF2196F3);
      default:
        return Color(0xFF4CAF50);
    }
  }

  IconData _getStatusIcon() {
    if (_budget.isUpcoming) {
      return Icons.schedule;
    }

    switch (_budget.status) {
      case BudgetStatus.exceeded:
        return Icons.warning;
      case BudgetStatus.completed:
        return Icons.check_circle;
      case BudgetStatus.upcoming:
        return Icons.schedule;
      default:
        return Icons.trending_up;
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
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          localizations.budgetDetails,
          style: GoogleFonts.poppins(
            fontSize: responsive.fs20,
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
            onPressed: (_isRefreshing || _isDeleting) ? null : _refreshBudget,
          ),
          IconButton(
            icon: Icon(Icons.edit, color: Color(0xFF667eea)),
            onPressed: _isDeleting ? null : () => _navigateToEditBudget(),
          ),
          IconButton(
            icon: _isDeleting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                  )
                : Icon(Icons.delete, color: Colors.red),
            onPressed: _isDeleting ? null : _showDeleteConfirmation,
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
            padding: responsive.padding(all: 20),
            children: [
              // Budget Overview Card
              Container(
              padding: responsive.padding(all: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _budget.isUpcoming
                      ? [Color(0xFF2196F3), Color(0xFF1976D2)]
                      : [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withOpacity(0.3),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _budget.name,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            // NEW: Show currency
                            Text(
                              _budget.currency.displayName,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs14,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: responsive.padding(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(_getStatusIcon(), color: Colors.white, size: responsive.icon16),
                            SizedBox(width: responsive.sp4),
                            Text(
                              _getStatusLabel(),
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: responsive.sp8),
                  Text(
                    _budget.period.name.toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs12,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  if (_budget.description != null) ...[
                    SizedBox(height: responsive.sp8),
                    Text(
                      _budget.description!,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs13,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                  SizedBox(height: responsive.sp20),

                  // NEW: Use display methods with currency
                  Text(
                    '${_budget.displayTotalSpent} / ${_budget.displayTotalBudget}',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: responsive.sp12),
                  LinearProgressIndicator(
                    value: _budget.percentageUsed / 100,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: responsive.spacing(mobile: 8),
                  ),
                  SizedBox(height: responsive.sp8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_budget.percentageUsed.toStringAsFixed(1)}% ${localizations.used}',
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs12,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      Text(
                        '${localizations.remaining}: ${_budget.displayRemainingBudget}',  // NEW: use display method
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

              if (_budget.isAutoCreated) ...[
              SizedBox(height: responsive.sp16),
              Container(
                padding: responsive.padding(all: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea).withOpacity(0.1),
                      Color(0xFF764ba2).withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  border: Border.all(color: Color(0xFF667eea).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.autorenew,
                      color: Color(0xFF667eea),
                      size: responsive.icon20,
                    ),
                    SizedBox(width: responsive.sp8),
                    Expanded(
                      child: Text(
                        _budget.autoCreateWithAi
                            ? localizations.budgetWasAutomaticallyCreatedAi
                            : localizations.budgetWasAutomaticallyCreatedPrevious,
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs12,
                          color: Color(0xFF667eea),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // NEW: Show auto-create status
            if (_budget.autoCreateEnabled) ...[
              SizedBox(height: responsive.sp16),
              Container(
                padding: responsive.padding(all: 12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.autorenew,
                      color: Colors.green[700],
                      size: responsive.icon20,
                    ),
                    SizedBox(width: responsive.sp8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            localizations.autoCreateEnabled,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs13,
                              fontWeight: FontWeight.w600,
                              color: Colors.green[900],
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            _budget.autoCreateWithAi
                                ? localizations.nextBudgetWillBeAiOptimized
                                : localizations.nextBudgetWillUseSameAmounts,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs11,
                              color: Colors.green[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],


              // Update the info banner section
              if (_budget.isUpcoming) ...[
                SizedBox(height: responsive.sp16),
                Container(
                  padding: responsive.padding(all: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue[700],
                        size: responsive.icon20,
                      ),
                      SizedBox(width: responsive.sp8),
                      Expanded(
                        child: Text(
                          'This budget will start on ${DateFormat('MMMM dd, yyyy').format(_budget.startDate)}. No spending is tracked yet.',
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs12,
                            color: Colors.blue[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (!_budget.isActive &&
                  DateTime.now().toUtc().isAfter(_budget.endDate.toUtc())) ...[
                SizedBox(height: responsive.sp16),
                Container(
                  padding: responsive.padding(all: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.grey[600],
                        size: responsive.icon20,
                      ),
                      SizedBox(width: responsive.sp8),
                      Expanded(
                        child: Text(
                          'This budget ended on ${DateFormat('MMMM dd, yyyy').format(_budget.endDate)}',
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs12,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Rest of the UI remains the same...
              SizedBox(height: responsive.sp24),

              // Budget Period Info
              Container(
                padding: responsive.padding(all: 16),
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
                child: Column(
                  children: [
                    _buildInfoRow(
                      Icons.calendar_today,
                      localizations.startDate,
                      DateFormat('MMMM dd, yyyy').format(_budget.startDate),
                    ),
                    Divider(height: 24),
                    _buildInfoRow(
                      Icons.event,
                      localizations.endDateNoOp,
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

              SizedBox(height: responsive.sp24),

              // Category Budgets
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    localizations.categoryBudgets,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                  Text(
                    '${_budget.categoryBudgets.length} ${localizations.categories}',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),

              SizedBox(height: responsive.sp12),

              ..._budget.categoryBudgets.map((catBudget) {
              return _buildCategoryCard(catBudget);
            }).toList(),
              SizedBox(height: responsive.sp24),

              // Budget Tips
              if (_budget.status == BudgetStatus.exceeded)
                Container(
                  padding: responsive.padding(all: 16),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red[700]),
                      SizedBox(width: responsive.sp12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizations.budgetExceeded,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs14,
                                fontWeight: FontWeight.w600,
                                color: Colors.red[900],
                              ),
                            ),
                            Text(
                              localizations.budgetExceededAlert,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs12,
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
                  padding: responsive.padding(all: 16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange[700]),
                      SizedBox(width: responsive.sp12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizations.approachingBudgetLimit,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs14,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange[900],
                              ),
                            ),
                            Text(
                              'You\'ve used ${_budget.percentageUsed.toStringAsFixed(1)}% of your budget. Track your spending carefully.',
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs12,
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
    final responsive = ResponsiveHelper(context);
    return Row(
      children: [
        Icon(icon, color: Color(0xFF667eea), size: responsive.icon20),
        SizedBox(width: responsive.sp12),
        Text(
          '$label:',
          style: GoogleFonts.poppins(fontSize: responsive.fs13, color: Colors.grey[600]),
        ),
        Spacer(),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: responsive.fs13,
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

    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: responsive.padding(all: 16),
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
                      padding: responsive.padding(all: 8),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                      ),
                      child: Icon(Icons.category, color: statusColor, size: responsive.icon18),
                    ),
                    SizedBox(width: responsive.sp12),
                    Expanded(
                      child: Text(
                        catBudget.mainCategory,
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs14,
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
                  padding: responsive.padding(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                  ),
                  child: Text(
                    localizations.exceeded,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs10,
                      fontWeight: FontWeight.w600,
                      color: Colors.red[700],
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: responsive.sp12),
          Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_budget.currency.symbol}${formatter.format(catBudget.spentAmount)}', // Changed
              style: GoogleFonts.poppins(
                fontSize: responsive.fs16,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
            Text(
              '${_budget.currency.symbol}${formatter.format(catBudget.allocatedAmount)}', // Changed
              style: GoogleFonts.poppins(
                fontSize: responsive.fs14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
          SizedBox(height: responsive.sp8),
          LinearProgressIndicator(
            value: catBudget.percentageUsed / 100,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            minHeight: responsive.spacing(mobile: 6),
          ),
          SizedBox(height: responsive.sp4),
          Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${catBudget.percentageUsed.toStringAsFixed(1)}% ${localizations.used}',
              style: GoogleFonts.poppins(
                fontSize: responsive.fs11,
                color: Colors.grey[600],
              ),
            ),
            Text(
              '${localizations.remaining}: ${_budget.currency.symbol}${formatter.format(catBudget.allocatedAmount - catBudget.spentAmount)}', // Changed
              style: GoogleFonts.poppins(
                fontSize: responsive.fs11,
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
