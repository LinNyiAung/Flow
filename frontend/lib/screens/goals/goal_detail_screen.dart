import 'package:flutter/material.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/goal.dart';
import '../../providers/goal_provider.dart';
import '../../providers/transaction_provider.dart';
import 'package:frontend/services/responsive_helper.dart';

class GoalDetailScreen extends StatefulWidget {
  final Goal goal;

  GoalDetailScreen({required this.goal});

  @override
  _GoalDetailScreenState createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  final _contributionController = TextEditingController();
  bool _isLoading = false;
  bool _isContributionLoading = false; // NEW: Separate loading state for contribution dialog
  late Goal _currentGoal;
  
  @override
  void initState() {
    super.initState();
    _currentGoal = widget.goal;
  }

  @override
  void dispose() {
    _contributionController.dispose();
    super.dispose();
  }

  Future<void> _refreshGoalData() async {
    final goalProvider = Provider.of<GoalProvider>(context, listen: false);
    final updatedGoal = await goalProvider.getGoal(_currentGoal.id);
    if (updatedGoal != null) {
      setState(() {
        _currentGoal = updatedGoal;
      });
    }
  }

  Future<void> _contributeToGoal(bool isAdd) async {
    final localizations = AppLocalizations.of(context);
    if (_contributionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.validationAmountRequired, style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final amount = double.tryParse(_contributionController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.pleaseEnterAValidAmount, style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isContributionLoading = true; // NEW: Set contribution loading state
    });

    final goalProvider = Provider.of<GoalProvider>(context, listen: false);
    final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);

    final success = await goalProvider.contributeToGoal(
      goalId: _currentGoal.id,
      amount: isAdd ? amount : -amount,
    );

    setState(() {
      _isContributionLoading = false; // NEW: Reset contribution loading state
    });

    if (success) {
      await transactionProvider.fetchBalance();
      _contributionController.clear();
      Navigator.pop(context); // Close dialog
      await _refreshGoalData(); // Refresh the goal data
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAdd ? localizations.fundsAddedSuccessfully : localizations.fundsWithdrawnSuccessfully,
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      Navigator.pop(context); // Close dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            goalProvider.error ?? 'Operation failed',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showContributionDialog() {
  final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
  
  // Fetch balance for the goal's currency
  transactionProvider.fetchBalance(currency: _currentGoal.currency);
  
  final availableBalance = transactionProvider.balance != null && 
                          transactionProvider.balance!.currency == _currentGoal.currency
      ? transactionProvider.balance!.availableBalance 
      : 0.0;

  _isContributionLoading = false;
  final responsive = ResponsiveHelper(context);
  final localizations = AppLocalizations.of(context);
  showDialog(
    context: context,
    barrierDismissible: !_isContributionLoading,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(16))),
        title: Text(localizations.manageFunds, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // UPDATE to show currency symbol
            Text(
              '${localizations.available}: ${_currentGoal.currency.symbol}${availableBalance.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                fontSize: responsive.fs14, 
                color: Color(0xFF667eea), 
                fontWeight: FontWeight.w600
              ),
            ),
            SizedBox(height: responsive.sp4),
            Text(
              '${localizations.currency}: ${_currentGoal.currency.displayName}',
              style: GoogleFonts.poppins(
                fontSize: responsive.fs12, 
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: responsive.sp16),
            TextField(
              controller: _contributionController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              enabled: !_isContributionLoading,
              decoration: InputDecoration(
                labelText: localizations.amountLabel,
                
                // UPDATE hint to show currency symbol
                prefixText: '${_currentGoal.currency.symbol} ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(12))),
              ),
            ),
          ],
        ),
        actions: [
            TextButton(
              onPressed: _isContributionLoading ? null : () => Navigator.pop(context), // NEW: Disable while loading
              child: Text(localizations.dialogCancel, style: GoogleFonts.poppins(color: _isContributionLoading ? Colors.grey : Colors.grey[600])),
            ),
            if (_currentGoal.currentAmount > 0)
              ElevatedButton(
                onPressed: _isContributionLoading ? null : () async { // NEW: Disable while loading
                  setDialogState(() {
                    _isContributionLoading = true;
                  });
                  await _contributeToGoal(false);
                  if (mounted) {
                    setDialogState(() {
                      _isContributionLoading = false;
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isContributionLoading ? Colors.grey : Color(0xFFFF5722),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(8))),
                ),
                child: _isContributionLoading
                    ? SizedBox(
                        height: responsive.iconSize(mobile: 16),
                        width: responsive.iconSize(mobile: 16),
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(localizations.withdraw, style: GoogleFonts.poppins(color: Colors.white)),
              ),
            if (_currentGoal.status == GoalStatus.active)
              ElevatedButton(
                onPressed: _isContributionLoading ? null : () async { // NEW: Disable while loading
                  setDialogState(() {
                    _isContributionLoading = true;
                  });
                  await _contributeToGoal(true);
                  if (mounted) {
                    setDialogState(() {
                      _isContributionLoading = false;
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isContributionLoading ? Colors.grey : Color(0xFF4CAF50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(8))),
                ),
                child: _isContributionLoading
                    ? SizedBox(
                        height: responsive.iconSize(mobile: 16),
                        width: responsive.iconSize(mobile: 16),
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(localizations.add, style: GoogleFonts.poppins(color: Colors.white)),
              ),
          ],
      ),
    ),
  );
}

  void _showEditDialog() {
    final _nameController = TextEditingController(text: _currentGoal.name);
    final _targetAmountController = TextEditingController(text: _currentGoal.targetAmount.toString());
    DateTime? _targetDate = _currentGoal.targetDate;
    GoalType _selectedGoalType = _currentGoal.goalType;
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(16))),
          title: Text(localizations.editGoal, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: localizations.goalName,
                    prefixIcon: Icon(Icons.label, color: Color(0xFF667eea)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(12))),
                  ),
                ),
                SizedBox(height: responsive.sp16),
                DropdownButtonFormField<GoalType>(
                  value: _selectedGoalType,
                  decoration: InputDecoration(
                    labelText: localizations.goalType,
                    prefixIcon: Icon(Icons.category, color: Color(0xFF667eea)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(12))),
                  ),
                  isExpanded: true, // ADD THIS LINE - prevents overflow
                  items: GoalType.values.map((type) {
                    IconData icon;
                    switch (type) {
                      case GoalType.savings:
                        icon = Icons.savings;
                        break;
                      case GoalType.debt_reduction:
                        icon = Icons.money_off;
                        break;
                      case GoalType.large_purchase:
                        icon = Icons.shopping_bag;
                        break;
                    }
                    return DropdownMenuItem(
                      value: type,
                      child: Row(
                        children: [
                          Icon(icon, size: responsive.icon20, color: Color(0xFF667eea)),
                          SizedBox(width: responsive.sp8),
                          Flexible( // WRAP Text with Flexible
                            child: Text(
                              type.name.replaceAll('_', ' ').toUpperCase(),
                              style: GoogleFonts.poppins(fontSize: responsive.fs14),
                              overflow: TextOverflow.ellipsis, // Handle long text
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      _selectedGoalType = value!;
                    });
                  },
                ),
                SizedBox(height: responsive.sp16),
                TextField(
                  controller: _targetAmountController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: localizations.targetAmount,
                    prefixIcon: Icon(Icons.attach_money, color: Color(0xFF667eea)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(12))),
                  ),
                ),
                SizedBox(height: responsive.sp16),
                InkWell(
                  onTap: () async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: _targetDate ?? DateTime.now().add(Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(Duration(days: 3650)),
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.light().copyWith(
                            primaryColor: Color(0xFF667eea),
                            colorScheme: ColorScheme.light(primary: Color(0xFF667eea)),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setDialogState(() {
                        _targetDate = picked;
                      });
                    }
                  },
                  child: Container(
                    padding: responsive.padding(all: 15),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: Color(0xFF667eea)),
                        SizedBox(width: responsive.sp12),
                        Expanded(
                          child: Text(
                            _targetDate == null
                                ? localizations.selectTargetDate
                                : DateFormat('MMM dd, yyyy').format(_targetDate!),
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs14,
                              color: _targetDate == null ? Colors.grey[600] : Color(0xFF333333),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(localizations.dialogCancel, style: GoogleFonts.poppins(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(localizations.enterAGoalName, style: GoogleFonts.poppins(color: Colors.white)),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                final targetAmount = double.tryParse(_targetAmountController.text);
                if (targetAmount == null || targetAmount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(localizations.pleaseEnterAValidAmount, style: GoogleFonts.poppins(color: Colors.white)),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                Navigator.pop(context); // Close dialog
                setState(() {
                  _isLoading = true;
                });

                final goalProvider = Provider.of<GoalProvider>(context, listen: false);
                final success = await goalProvider.updateGoal(
                  goalId: _currentGoal.id,
                  name: _nameController.text.trim(),
                  targetAmount: targetAmount,
                  targetDate: _targetDate,
                  goalType: _selectedGoalType,
                );

                setState(() {
                  _isLoading = false;
                });

                if (success) {
                  await _refreshGoalData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(localizations.goalUpdatedSuccessfully, style: GoogleFonts.poppins(color: Colors.white)),
                      backgroundColor: Color(0xFF4CAF50),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(goalProvider.error ?? localizations.failedToUpdateGoal, style: GoogleFonts.poppins(color: Colors.white)),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF667eea),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(8))),
              ),
              child: Text(localizations.save, style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog() {
  final responsive = ResponsiveHelper(context);
  final localizations = AppLocalizations.of(context);
  bool _isDeleteLoading = false;
  
  showDialog(
    context: context,
    barrierDismissible: false, // Prevent dismissal while deleting
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(16))),
        title: Text(localizations.deleteGoal, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
          localizations.deleteGoalConfirmation,
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: _isDeleteLoading ? null : () => Navigator.pop(context),
            child: Text(
              localizations.dialogCancel, 
              style: GoogleFonts.poppins(color: _isDeleteLoading ? Colors.grey : Colors.grey[600])
            ),
          ),
          ElevatedButton(
            onPressed: _isDeleteLoading ? null : () async {
              setDialogState(() {
                _isDeleteLoading = true;
              });
              _deleteGoal();
              // Don't reset loading state here as we're navigating away
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _isDeleteLoading ? Colors.grey : Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(8))),
            ),
            child: _isDeleteLoading
                ? SizedBox(
                    height: responsive.iconSize(mobile: 16),
                    width: responsive.iconSize(mobile: 16),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(localizations.delete, style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    ),
  );
}

  void _deleteGoal() async {
  final goalProvider = Provider.of<GoalProvider>(context, listen: false);
  final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
  final localizations = AppLocalizations.of(context);
  final success = await goalProvider.deleteGoal(_currentGoal.id);

  if (success) {
    await transactionProvider.fetchBalance();
    Navigator.pop(context); // Close dialog
    Navigator.pop(context, 'deleted'); // Go back to goals screen
  } else {
    Navigator.pop(context); // Close dialog
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(goalProvider.error ?? localizations.failedToDeleteGoal, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    IconData goalIcon;
    Color goalColor;
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);

    switch (_currentGoal.goalType) {
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          localizations.goalDetails,
          style: GoogleFonts.poppins(
            fontSize: responsive.fs20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Color(0xFF333333)),
          onPressed: () => Navigator.pop(context, true),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.edit, color: Color(0xFF667eea)),
            onPressed: _showEditDialog,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.red),
            onPressed: _showDeleteDialog,
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
        child: SingleChildScrollView(
          padding: responsive.padding(all: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Goal Header Card
              Container(
                width: double.infinity,
                padding: responsive.padding(all: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [goalColor, goalColor.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
                  boxShadow: [
                    BoxShadow(
                      color: goalColor.withOpacity(0.3),
                      spreadRadius: 2,
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: responsive.padding(all: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                          ),
                          child: Icon(goalIcon, color: Colors.white, size: responsive.iconSize(mobile: 32)),
                        ),
                        SizedBox(width: responsive.sp16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentGoal.name,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: responsive.fs22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _currentGoal.goalType.name.replaceAll('_', ' ').toUpperCase(),
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: responsive.fs12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_currentGoal.status == GoalStatus.achieved)
                          Container(
                            padding: responsive.padding(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                            ),
                            child: Text(
                              localizations.achieved,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs12,
                                fontWeight: FontWeight.w600,
                                color: goalColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: responsive.sp24),
                    Text(
                      localizations.currentProgress,
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: responsive.fs14,
                      ),
                    ),
                    SizedBox(height: responsive.sp8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _currentGoal.displayCurrentAmount,  // UPDATED
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: responsive.fs32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'of ${_currentGoal.displayTargetAmount}',  // UPDATED
                          style: GoogleFonts.poppins(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: responsive.fs16,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: responsive.sp16),
                    LinearProgressIndicator(
                      value: _currentGoal.progressPercentage / 100,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      minHeight: responsive.spacing(mobile: 10),
                    ),
                    SizedBox(height: responsive.sp8),
                    Text(
                      '${_currentGoal.progressPercentage.toStringAsFixed(1)}% ${localizations.completed}',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: responsive.fs16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: responsive.sp24),

              // Goal Details Card
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.goalInformation,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                    ),
                    SizedBox(height: responsive.sp16),
                    _buildInfoRow(localizations.targetAmount, _currentGoal.displayTargetAmount),
                    Divider(height: 24),
                    _buildInfoRow(localizations.currentAmount, _currentGoal.displayCurrentAmount),
                    Divider(height: 24),
                    _buildInfoRow(localizations.remaining, _currentGoal.displayRemainingAmount),
                    Divider(height: 24),
                    _buildInfoRow(localizations.currency, _currentGoal.currency.displayName),
                    if (_currentGoal.targetDate != null) ...[
                      Divider(height: 24),
                      _buildInfoRow(localizations.targetDateDetail, DateFormat('MMMM dd, yyyy').format(_currentGoal.targetDate!)),
                    ],
                    Divider(height: 24),
                    _buildInfoRow(localizations.created, DateFormat('MMMM dd, yyyy').format(_currentGoal.createdAt)),
                    if (_currentGoal.achievedAt != null) ...[
                      Divider(height: 24),
                      _buildInfoRow(localizations.achieved, DateFormat('MMMM dd, yyyy').format(_currentGoal.achievedAt!)),
                    ],
                  ],
                ),
              ),

              SizedBox(height: responsive.sp24),

              // Action Button
              if (_currentGoal.status == GoalStatus.active || _currentGoal.currentAmount > 0)
                SizedBox(
                  width: double.infinity,
                  height: responsive.cardHeight(baseHeight: 52),
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _showContributionDialog, // NEW: Disable while loading
                    icon: Icon(Icons.account_balance_wallet, color: Colors.white),
                    label: Text(
                      localizations.manageFunds,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isLoading ? Colors.grey : Color(0xFF667eea),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                      ),
                      elevation: 4,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final responsive = ResponsiveHelper(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: responsive.fs14,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: responsive.fs14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
      ],
    );
  }
}