import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/goal.dart';
import '../../providers/goal_provider.dart';
import '../../providers/transaction_provider.dart';

class GoalDetailScreen extends StatefulWidget {
  final Goal goal;

  GoalDetailScreen({required this.goal});

  @override
  _GoalDetailScreenState createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  final _contributionController = TextEditingController();
  bool _isLoading = false;
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
    if (_contributionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter an amount', style: GoogleFonts.poppins(color: Colors.white)),
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
          content: Text('Please enter a valid amount', style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final goalProvider = Provider.of<GoalProvider>(context, listen: false);
    final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);

    final success = await goalProvider.contributeToGoal(
      goalId: _currentGoal.id,
      amount: isAdd ? amount : -amount,
    );

    setState(() {
      _isLoading = false;
    });

    if (success) {
      await transactionProvider.fetchBalance();
      _contributionController.clear();
      Navigator.pop(context); // Close dialog
      await _refreshGoalData(); // Refresh the goal data
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAdd ? 'Funds added successfully!' : 'Funds withdrawn successfully!',
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
    final availableBalance = transactionProvider.balance?.availableBalance ?? 0.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Manage Funds', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available: \$${availableBalance.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(fontSize: 14, color: Color(0xFF667eea), fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _contributionController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixIcon: Icon(Icons.attach_money, color: Color(0xFF667eea)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey[600])),
          ),
          if (_currentGoal.currentAmount > 0)
            ElevatedButton(
              onPressed: () => _contributeToGoal(false),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFFF5722),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Withdraw', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          if (_currentGoal.status == GoalStatus.active)
            ElevatedButton(
              onPressed: () => _contributeToGoal(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF4CAF50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Add', style: GoogleFonts.poppins(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  void _showEditDialog() {
    final _nameController = TextEditingController(text: _currentGoal.name);
    final _targetAmountController = TextEditingController(text: _currentGoal.targetAmount.toString());
    DateTime? _targetDate = _currentGoal.targetDate;
    GoalType _selectedGoalType = _currentGoal.goalType;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Edit Goal', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Goal Name',
                    prefixIcon: Icon(Icons.label, color: Color(0xFF667eea)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                SizedBox(height: 16),
                DropdownButtonFormField<GoalType>(
                  value: _selectedGoalType,
                  decoration: InputDecoration(
                    labelText: 'Goal Type',
                    prefixIcon: Icon(Icons.category, color: Color(0xFF667eea)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
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
                          Icon(icon, size: 20, color: Color(0xFF667eea)),
                          SizedBox(width: 8),
                          Text(
                            type.name.replaceAll('_', ' ').toUpperCase(),
                            style: GoogleFonts.poppins(fontSize: 14),
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
                SizedBox(height: 16),
                TextField(
                  controller: _targetAmountController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Target Amount',
                    prefixIcon: Icon(Icons.attach_money, color: Color(0xFF667eea)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                SizedBox(height: 16),
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
                    padding: EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: Color(0xFF667eea)),
                        SizedBox(width: 12),
                        Text(
                          _targetDate == null
                              ? 'Select target date (Optional)'
                              : DateFormat('MMM dd, yyyy').format(_targetDate!),
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: _targetDate == null ? Colors.grey[600] : Color(0xFF333333),
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
              child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please enter a goal name', style: GoogleFonts.poppins(color: Colors.white)),
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
                      content: Text('Please enter a valid target amount', style: GoogleFonts.poppins(color: Colors.white)),
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
                      content: Text('Goal updated successfully!', style: GoogleFonts.poppins(color: Colors.white)),
                      backgroundColor: Color(0xFF4CAF50),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(goalProvider.error ?? 'Failed to update goal', style: GoogleFonts.poppins(color: Colors.white)),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF667eea),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Save', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Goal', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete this goal? The allocated funds will be returned to your balance.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _deleteGoal(); // Call delete function
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteGoal() async {
    setState(() {
      _isLoading = true;
    });

    final goalProvider = Provider.of<GoalProvider>(context, listen: false);
    final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);

    final success = await goalProvider.deleteGoal(_currentGoal.id);

    if (success) {
      await transactionProvider.fetchBalance();
      Navigator.pop(context, 'deleted'); // Go back to goals screen
      // No setState here since we're leaving the screen
    } else {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(goalProvider.error ?? 'Failed to delete goal', style: GoogleFonts.poppins(color: Colors.white)),
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
          'Goal Details',
          style: GoogleFonts.poppins(
            fontSize: 20,
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
      body: _isLoading
          ? Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
        ),
      )
          : Container(
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
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Goal Header Card
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [goalColor, goalColor.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(20),
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
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(goalIcon, color: Colors.white, size: 32),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentGoal.name,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _currentGoal.goalType.name.replaceAll('_', ' ').toUpperCase(),
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_currentGoal.status == GoalStatus.achieved)
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Achieved',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: goalColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Current Progress',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '\$${_currentGoal.currentAmount.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'of \$${_currentGoal.targetAmount.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _currentGoal.progressPercentage / 100,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      minHeight: 10,
                    ),
                    SizedBox(height: 8),
                    Text(
                      '${_currentGoal.progressPercentage.toStringAsFixed(1)}% Complete',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Goal Details Card
              Container(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Goal Information',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                    ),
                    SizedBox(height: 16),
                    _buildInfoRow('Target Amount', '\$${_currentGoal.targetAmount.toStringAsFixed(2)}'),
                    Divider(height: 24),
                    _buildInfoRow('Current Amount', '\$${_currentGoal.currentAmount.toStringAsFixed(2)}'),
                    Divider(height: 24),
                    _buildInfoRow('Remaining', '\$${(_currentGoal.targetAmount - _currentGoal.currentAmount).toStringAsFixed(2)}'),
                    if (_currentGoal.targetDate != null) ...[
                      Divider(height: 24),
                      _buildInfoRow('Target Date', DateFormat('MMMM dd, yyyy').format(_currentGoal.targetDate!)),
                    ],
                    Divider(height: 24),
                    _buildInfoRow('Created', DateFormat('MMMM dd, yyyy').format(_currentGoal.createdAt)),
                    if (_currentGoal.achievedAt != null) ...[
                      Divider(height: 24),
                      _buildInfoRow('Achieved', DateFormat('MMMM dd, yyyy').format(_currentGoal.achievedAt!)),
                    ],
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Action Button
              if (_currentGoal.status == GoalStatus.active || _currentGoal.currentAmount > 0)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _showContributionDialog,
                    icon: Icon(Icons.account_balance_wallet, color: Colors.white),
                    label: Text(
                      'Manage Funds',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF667eea),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
      ],
    );
  }
}