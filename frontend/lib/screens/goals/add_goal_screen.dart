import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/goal.dart';
import '../../providers/goal_provider.dart';
import '../../providers/transaction_provider.dart';
import 'package:frontend/services/responsive_helper.dart';

class AddGoalScreen extends StatefulWidget {
  @override
  _AddGoalScreenState createState() => _AddGoalScreenState();
}

class _AddGoalScreenState extends State<AddGoalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _targetAmountController = TextEditingController();
  final _initialContributionController = TextEditingController();
  
  GoalType _selectedGoalType = GoalType.savings;
  DateTime? _targetDate;
  bool _isLoading = false;

  Currency _selectedCurrency = Currency.usd;


  @override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
    setState(() {
      _selectedCurrency = authProvider.defaultCurrency;
    });
    // Fetch balance for default currency
    transactionProvider.fetchBalance(currency: _selectedCurrency);
  });
}

  @override
  void dispose() {
    _nameController.dispose();
    _targetAmountController.dispose();
    _initialContributionController.dispose();
    super.dispose();
  }

  Future<void> _selectTargetDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(Duration(days: 30)),
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
      setState(() {
        _targetDate = picked;
      });
    }
  }

  Future<void> _createGoal() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() {
    _isLoading = true;
  });

  final goalProvider = Provider.of<GoalProvider>(context, listen: false);
  final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
  final responsive = ResponsiveHelper(context);
  final localizations = AppLocalizations.of(context);

  final success = await goalProvider.createGoal(
    name: _nameController.text.trim(),
    targetAmount: double.parse(_targetAmountController.text),
    targetDate: _targetDate,
    goalType: _selectedGoalType,
    initialContribution: _initialContributionController.text.isNotEmpty
        ? double.parse(_initialContributionController.text)
        : 0.0,
    currency: _selectedCurrency,  // ADD THIS LINE
  );

  setState(() {
    _isLoading = false;
  });

  if (success) {
    await transactionProvider.fetchBalance(currency: _selectedCurrency);  // Refresh balance
    Navigator.pop(context, true);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          goalProvider.error ?? localizations.failedToCreateGoal,
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(8))),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    final transactionProvider = Provider.of<TransactionProvider>(context);
    final availableBalance = transactionProvider.balance?.availableBalance ?? 0.0;
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          localizations.createNewGoal,
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Available Balance Card
                Container(
                  width: double.infinity,
                  padding: responsive.padding(all: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    ),
                    borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizations.availableForGoals,
                        style: GoogleFonts.poppins(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: responsive.fs14,
                        ),
                      ),
                      SizedBox(height: responsive.sp8),
                      Text(
                        _selectedCurrency.displayName,
                        style: GoogleFonts.poppins(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: responsive.fs12,
                        ),
                      ),
                      Text(
                        transactionProvider.balance != null && 
                        transactionProvider.balance!.currency == _selectedCurrency
                            ? '${_selectedCurrency.symbol}${transactionProvider.balance!.availableBalance.toStringAsFixed(2)}'
                            : '${_selectedCurrency.symbol}0.00',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: responsive.fs28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: responsive.sp24),

                // Currency Selector
                Text(
                  localizations.currency,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: responsive.sp8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  ),
                  child: DropdownButtonFormField<Currency>(
                    value: _selectedCurrency,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.currency_exchange, color: Color(0xFF667eea)),
                      border: InputBorder.none,
                      contentPadding: responsive.padding(horizontal: 15, vertical: 15),
                    ),
                    items: Currency.values.map((currency) {
                      return DropdownMenuItem(
                        value: currency,
                        child: Text(
                          '${currency.symbol} - ${currency.displayName}',
                          style: GoogleFonts.poppins(fontSize: responsive.fs14),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) async {
                      setState(() {
                        _selectedCurrency = value!;
                      });
                      // Fetch balance for selected currency
                      final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
                      await transactionProvider.fetchBalance(currency: _selectedCurrency);
                    },
                  ),
                ),

                SizedBox(height: responsive.sp24),

                // Goal Name
                Text(
                  localizations.goalName,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: responsive.sp8),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: localizations.egEmergencyFund,
                    prefixIcon: Icon(Icons.label, color: Color(0xFF667eea)),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return localizations.pleaseEnterAGoalName;
                    }
                    return null;
                  },
                ),

                SizedBox(height: responsive.sp20),

                // Goal Type
                Text(
                  localizations.goalType,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: responsive.sp8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  ),
                  child: DropdownButtonFormField<GoalType>(
                    value: _selectedGoalType,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.category, color: Color(0xFF667eea)),
                      border: InputBorder.none,
                      contentPadding: responsive.padding(horizontal: 15, vertical: 15),
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
                            Icon(icon, size: responsive.icon20, color: Color(0xFF667eea)),
                            SizedBox(width: responsive.sp8),
                            Text(
                              type.name.replaceAll('_', ' ').toUpperCase(),
                              style: GoogleFonts.poppins(fontSize: responsive.fs14),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedGoalType = value!;
                      });
                    },
                  ),
                ),

                SizedBox(height: responsive.sp20),

                // Target Amount
                Text(
                  localizations.targetAmount,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: responsive.sp8),
                TextFormField(
                  controller: _targetAmountController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixIcon: Icon(Icons.attach_money, color: Color(0xFF667eea)),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return localizations.pleaseEnterTargetAmount;
                    }
                    final amount = double.tryParse(value);
                    if (amount == null || amount <= 0) {
                      return localizations.pleaseEnterAValidAmount;
                    }
                    return null;
                  },
                ),

                SizedBox(height: responsive.sp20),

                // Initial Contribution
                Text(
                  localizations.initialContribution,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: responsive.sp8),
                TextFormField(
                  controller: _initialContributionController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixIcon: Icon(Icons.account_balance_wallet, color: Color(0xFF667eea)),
                  ),
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      final amount = double.tryParse(value);
                      if (amount == null || amount < 0) {
                        return localizations.pleaseEnterAValidAmount;
                      }
                      if (amount > availableBalance) {
                        return localizations.insufficientBalance;
                      }
                    }
                    return null;
                  },
                ),

                SizedBox(height: responsive.sp20),

                // Target Date
                Text(
                  localizations.targetDate,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: responsive.sp8),
                InkWell(
                  onTap: _selectTargetDate,
                  child: Container(
                    padding: responsive.padding(all: 15),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
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

                SizedBox(height: responsive.sp32),

                // Create Button
                SizedBox(
                  width: double.infinity,
                  height: responsive.cardHeight(baseHeight: 52),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createGoal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF667eea),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                      ),
                      elevation: 4,
                    ),
                    child: _isLoading
                        ? SizedBox(
                            height: responsive.iconSize(mobile: 20),
                            width: responsive.iconSize(mobile: 20),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            localizations.createGoal,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}