import 'package:flutter/material.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/budget.dart';
import '../../providers/budget_provider.dart';
import 'ai_budget_suggestion_screen.dart';

class CreateBudgetScreen extends StatefulWidget {
  @override
  _CreateBudgetScreenState createState() => _CreateBudgetScreenState();
}

class _CreateBudgetScreenState extends State<CreateBudgetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contextController = TextEditingController(); // NEW

  

  BudgetPeriod _selectedPeriod = BudgetPeriod.monthly;
  DateTime _startDate = DateTime.now().toUtc();
  DateTime? _endDate;
  List<CategoryBudget> _categoryBudgets = [];

  bool _isLoading = false;

  bool _autoCreateEnabled = false;
  bool _autoCreateWithAi = false;

  bool _showAiFeatures = false;


  Currency _selectedCurrency = Currency.usd;


  @override
  void initState() {
    super.initState();
    // NEW: Set default currency from user's preference
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      setState(() {
        _selectedCurrency = authProvider.defaultCurrency;
      });
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _contextController.dispose(); // NEW
    super.dispose();
  }

  void _calculateEndDate() {
    switch (_selectedPeriod) {
      case BudgetPeriod.weekly:
        // Calculate the start of the week (Monday)
        final daysSinceMonday =
            _startDate.weekday - 1; // Monday is 1, Sunday is 7
        final weekStart = DateTime.utc(
          _startDate.year,
          _startDate.month,
          _startDate.day - daysSinceMonday,
          0,
          0,
          0,
        );

        // End is Sunday (6 days after Monday)
        _endDate = DateTime.utc(
          weekStart.year,
          weekStart.month,
          weekStart.day + 6,
          23,
          59,
          59,
          999,
        );
        break;

      case BudgetPeriod.monthly:
        // Keep the selected start date, find last day of the month
        final monthStart = DateTime.utc(
          _startDate.year,
          _startDate.month,
          _startDate.day,
          0,
          0,
          0,
        );

        // Get last day of the current month
        final nextMonth = _startDate.month == 12
            ? DateTime.utc(_startDate.year + 1, 1, 1)
            : DateTime.utc(_startDate.year, _startDate.month + 1, 1);
        final lastDayOfMonth = nextMonth.subtract(Duration(days: 1));

        // Set end date to last day at 23:59:59 UTC
        _endDate = DateTime.utc(
          lastDayOfMonth.year,
          lastDayOfMonth.month,
          lastDayOfMonth.day,
          23,
          59,
          59,
          999,
        );
        break;

      case BudgetPeriod.yearly:
        // Keep the selected start date, end is Dec 31 of the same year
        final yearStart = DateTime.utc(
          _startDate.year,
          _startDate.month,
          _startDate.day,
          0,
          0,
          0,
        );

        _endDate = DateTime.utc(_startDate.year, 12, 31, 23, 59, 59, 999);
        break;

      case BudgetPeriod.custom:
        // For custom, end date is set by user
        break;
    }
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: Color(0xFF667eea)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        // Set start date to beginning of day in UTC
        _startDate = DateTime.utc(
          picked.year,
          picked.month,
          picked.day,
          0,
          0,
          0,
        );
        if (_selectedPeriod != BudgetPeriod.custom) {
          _calculateEndDate();
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(Duration(days: 30)),
      firstDate: _startDate,
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: Color(0xFF667eea)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        // Set end date to end of day in UTC
        _endDate = DateTime.utc(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
          999,
        );
      });
    }
  }

  String? _validateDuplicateCategory(String mainCategory, String? subCategory) {
    // Check for exact duplicates
    for (var existingCat in _categoryBudgets) {
      String existingMain = existingCat.mainCategory;
      String? existingSubStr;

      // Parse existing category
      if (existingMain.contains(' - ')) {
        final parts = existingMain.split(' - ');
        existingMain = parts[0];
        existingSubStr = parts[1];
      }

      // Check if it's the same main category with same sub-category (or both have no sub-category)
      if (existingMain == mainCategory) {
        if ((subCategory == null || subCategory == 'All') &&
            existingSubStr == null) {
          return 'This category already exists';
        }
        if (subCategory != null &&
            subCategory != 'All' &&
            existingSubStr == subCategory) {
          return 'This category already exists';
        }
      }
    }
    return null;
  }

  // In create_budget_screen.dart, replace the totalBudget calculation
  double _calculateTotalBudget() {
    Set<String> mainCategories = {};
    List<MapEntry<String, double>> subCategories = [];

    // Separate main categories and sub-categories
    for (var cat in _categoryBudgets) {
      if (cat.mainCategory.contains(' - ')) {
        final parts = cat.mainCategory.split(' - ');
        subCategories.add(MapEntry(parts[0], cat.allocatedAmount));
      } else {
        mainCategories.add(cat.mainCategory);
      }
    }

    double total = 0.0;

    // Add all main category budgets
    for (var cat in _categoryBudgets) {
      if (!cat.mainCategory.contains(' - ')) {
        total += cat.allocatedAmount;
      }
    }

    // Add sub-category budgets only if their main category doesn't exist
    for (var entry in subCategories) {
      if (!mainCategories.contains(entry.key)) {
        total += entry.value;
      }
    }

    return total;
  }

  void _addCategoryBudget() {
    showDialog(
      context: context,
      builder: (context) => _AddCategoryDialog(
        onAdd: (categoryBudget) {
          setState(() {
            _categoryBudgets.add(categoryBudget);
          });
        },
      ),
    );
  }

  void _editCategoryBudget(int index) {
    showDialog(
      context: context,
      builder: (context) => _AddCategoryDialog(
        initialCategory: _categoryBudgets[index],
        onAdd: (categoryBudget) {
          setState(() {
            _categoryBudgets[index] = categoryBudget;
          });
        },
      ),
    );
  }

  void _removeCategoryBudget(int index) {
    setState(() {
      _categoryBudgets.removeAt(index);
    });
  }

void _navigateToAISuggestion() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (!authProvider.isPremium) {
      Navigator.pushNamed(context, '/subscription');
      return;
    }

    if (_selectedPeriod == BudgetPeriod.custom && _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select end date for custom period'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final userContext = _contextController.text.trim().isEmpty
        ? null
        : _contextController.text.trim();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIBudgetSuggestionScreen(
          period: _selectedPeriod,
          startDate: _startDate,
          endDate: _endDate,
          userContext: userContext,
          currency: _selectedCurrency,  // NEW: pass currency
        ),
      ),
    );

    if (result != null && result is AIBudgetSuggestion) {
      setState(() {
        _nameController.text = result.suggestedName;
        _categoryBudgets = result.categoryBudgets;
        // Currency should match what was used for AI suggestion
      });
    }
  }

  Future<void> _saveBudget() async {
    if (!_formKey.currentState!.validate()) return;

    if (_categoryBudgets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please add at least one category budget'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedPeriod == BudgetPeriod.custom && _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select end date for custom period'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final totalBudget = _calculateTotalBudget();

    final success = await Provider.of<BudgetProvider>(context, listen: false)
        .createBudget(
          name: _nameController.text,
          period: _selectedPeriod,
          startDate: _startDate,
          endDate: _endDate,
          categoryBudgets: _categoryBudgets,
          totalBudget: totalBudget,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          autoCreateEnabled: _autoCreateEnabled,
          autoCreateWithAi: _autoCreateWithAi,
          currency: _selectedCurrency,  // NEW: add currency
        );

    setState(() => _isLoading = false);

    if (success) {
      Navigator.pop(context, true);
    } else {
      final error = Provider.of<BudgetProvider>(context, listen: false).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Failed to create budget'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _calculateEndDate();

    final totalBudget = _calculateTotalBudget();
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Create Budget',
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
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF667eea).withOpacity(0.1), Colors.white],
          ),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.all(20),
            children: [
              // NEW: Currency Selector (Add this BEFORE the AI Features section)
              Text(
                'Currency',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                ),
              ),
              SizedBox(height: 8),
              Container(
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
                child: DropdownButtonFormField<Currency>(
                  decoration: InputDecoration(
                    hintText: 'Select currency for this budget',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(15),
                    prefixIcon: Icon(Icons.attach_money, color: Color(0xFF667eea)),
                  ),
                  value: _selectedCurrency,
                  items: Currency.values.map((currency) {
                    return DropdownMenuItem(
                      value: currency,
                      child: Text(
                        '${currency.symbol} - ${currency.displayName}',
                        style: GoogleFonts.poppins(fontSize: 14),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCurrency = value!;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Please select a currency';
                    }
                    return null;
                  },
                ),
              ),
              SizedBox(height: 12),
              
              // Info note about currency
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Color(0xFF2196F3).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF2196F3), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Only transactions in ${_selectedCurrency.displayName} will affect this budget',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Color(0xFF2196F3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24),
              // NEW: Collapsible AI Features Section
              Container(
                margin: EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Color(0xFF667eea).withOpacity(0.3)),
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
                    // Toggle Header
                    InkWell(
                      onTap: () {
                        setState(() {
                          _showAiFeatures = !_showAiFeatures;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF667eea).withOpacity(0.2),
                                    Color(0xFF764ba2).withOpacity(0.2),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.auto_awesome,
                                color: Color(0xFF667eea),
                                size: 24,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'AI Features',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF333333),
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      if (!authProvider.isPremium)
                                        Icon(Icons.lock, size: 16, color: Color(0xFFFFD700)),
                                        SizedBox(width: 8),
                                      if (!authProvider.isPremium)
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Color(0xFFFFD700).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Color(0xFFFFD700), width: 1),
                                        ),
                                        child: Text(
                                          'PREMIUM',
                                          style: GoogleFonts.poppins(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFFFD700),
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                  Text(
                                    _showAiFeatures
                                        ? 'Get AI-powered budget suggestions'
                                        : 'Tap to use AI budget suggestions',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              _showAiFeatures
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: Color(0xFF667eea),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Collapsible Content
                    if (_showAiFeatures) ...[
                      Divider(height: 1),
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // AI Context Input
                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Color(0xFF667eea).withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Color(0xFF667eea).withOpacity(0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.lightbulb_outline,
                                        color: Color(0xFF667eea),
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Context (Optional)',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF333333),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Add context to help AI create better budgets',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  TextFormField(
                                    controller: _contextController,
                                    decoration: InputDecoration(
                                      hintText:
                                          'e.g., "Traveling this week" or "Holiday season"',
                                      hintStyle: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.grey[400],
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey[300]!,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey[300]!,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Color(0xFF667eea),
                                          width: 2,
                                        ),
                                      ),
                                      prefixIcon: Icon(
                                        Icons.note_alt_outlined,
                                        color: Color(0xFF667eea),
                                      ),
                                      counterText: '',
                                    ),
                                    maxLines: 2,
                                    maxLength: 200,
                                  ),
                                ],
                              ),
                            ),

                            SizedBox(height: 16),

                            // Generate Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _navigateToAISuggestion,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF667eea),
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Generate AI Budget',
                                      style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            SizedBox(height: 8),

                            // Info note
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 14,
                                  color: Color(0xFF667eea),
                                ),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'AI will analyze your spending and suggest category budgets',
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: Color(0xFF667eea),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Name Field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Budget Name',
                  hintText: 'e.g., Monthly Expenses',
                  prefixIcon: Icon(Icons.label, color: Color(0xFF667eea)),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter budget name';
                  }
                  return null;
                },
              ),

              SizedBox(height: 16),

              // Period Selector
              Text(
                'Budget Period',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                ),
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(4),
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
                child: Row(
                  children: [
                    _buildPeriodButton('Week', BudgetPeriod.weekly),
                    _buildPeriodButton('Month', BudgetPeriod.monthly),
                    _buildPeriodButton('Year', BudgetPeriod.yearly),
                    _buildPeriodButton('Custom', BudgetPeriod.custom),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Date Selection
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectStartDate,
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start Date',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              DateFormat('MMM d, yyyy').format(_startDate),
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectedPeriod == BudgetPeriod.custom
                          ? _selectEndDate
                          : null,
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _selectedPeriod == BudgetPeriod.custom
                              ? Colors.white
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End Date',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              _endDate != null
                                  ? DateFormat('MMM d, yyyy').format(_endDate!)
                                  : 'Auto',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 16),

              // Description Field
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'Notes about this budget',
                  prefixIcon: Icon(Icons.note, color: Color(0xFF667eea)),
                ),
                maxLines: 2,
              ),

              SizedBox(height: 24),

              if (_selectedPeriod != BudgetPeriod.custom) ...[
                SizedBox(height: 24),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF667eea).withOpacity(0.1),
                        Color(0xFF764ba2).withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Color(0xFF667eea).withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.autorenew, color: Color(0xFF667eea)),
                          SizedBox(width: 8),
                          Text(
                            'Auto-Create Next Budget',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Automatically create a new budget when this one ends',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: 12),
                      SwitchListTile(
                        value: _autoCreateEnabled,
                        onChanged: (value) {
                          setState(() {
                            _autoCreateEnabled = value;
                            if (!value) {
                              _autoCreateWithAi = false;
                            }
                          });
                        },
                        title: Text(
                          'Enable Auto-Create',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        activeColor: Color(0xFF667eea),
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_autoCreateEnabled) ...[
                        Divider(),
                        Text(
                          'Choose how to create the next budget:',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF333333),
                          ),
                        ),
                        SizedBox(height: 8),
                        RadioListTile<bool>(
                          value: false,
                          groupValue: _autoCreateWithAi,
                          onChanged: (value) {
                            setState(() {
                              _autoCreateWithAi = value!;
                            });
                          },
                          title: Text(
                            'Use Current Categories',
                            style: GoogleFonts.poppins(fontSize: 13),
                          ),
                          subtitle: Text(
                            'Keep the same budget amounts for all categories',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                          activeColor: Color(0xFF667eea),
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<bool>(
                          value: true,
                          groupValue: _autoCreateWithAi,
                          onChanged: (value) {
                            setState(() {
                              _autoCreateWithAi = value!;
                            });
                          },
                          title: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 16,
                                color: Color(0xFF667eea),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'AI-Optimized Budget',
                                style: GoogleFonts.poppins(fontSize: 13),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'AI analyzes your spending and suggests optimized amounts',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                          activeColor: Color(0xFF667eea),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              SizedBox(height: 24),

              // Category Budgets Section
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
                  TextButton.icon(
                    onPressed: _addCategoryBudget,
                    icon: Icon(Icons.add_circle, color: Color(0xFF667eea)),
                    label: Text(
                      'Add',
                      style: GoogleFonts.poppins(color: Color(0xFF667eea)),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 12),

              // Category Budgets List
              if (_categoryBudgets.isEmpty)
                Container(
                  padding: EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'No categories added yet',
                      style: GoogleFonts.poppins(color: Colors.grey[500]),
                    ),
                  ),
                )
              else
                ..._categoryBudgets.asMap().entries.map((entry) {
                  final index = entry.key;
                  final catBudget = entry.value;
                  return _buildCategoryBudgetCard(catBudget, index);
                }).toList(),

              SizedBox(height: 24),

              // Total Budget Display
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Budget',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${_selectedCurrency.symbol}${totalBudget.toStringAsFixed(2)}',  // NEW: use selected currency
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Save Button
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveBudget,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF667eea),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text(
                          'Create Budget',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
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
    );
  }

  Widget _buildPeriodButton(String label, BudgetPeriod period) {
    bool isSelected = _selectedPeriod == period;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedPeriod = period;
            if (period != BudgetPeriod.custom) {
              _calculateEndDate();
            }
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(colors: [Color(0xFF667eea), Color(0xFF764ba2)])
                : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBudgetCard(CategoryBudget catBudget, int index) {
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
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(0xFF667eea).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.category, color: Color(0xFF667eea), size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  catBudget.mainCategory,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                Text(
                  '\$${catBudget.allocatedAmount.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit, color: Color(0xFF667eea), size: 20),
            onPressed: () => _editCategoryBudget(index),
          ),
          IconButton(
            icon: Icon(Icons.delete, color: Colors.red, size: 20),
            onPressed: () => _removeCategoryBudget(index),
          ),
        ],
      ),
    );
  }
}


class _AddCategoryDialog extends StatefulWidget {
  final CategoryBudget? initialCategory;
  final Function(CategoryBudget) onAdd;

  _AddCategoryDialog({
    this.initialCategory,
    required this.onAdd,
  });

  @override
  _AddCategoryDialogState createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();

  String? _selectedMainCategory;
  String? _selectedSubCategory;
  List<Category> _categories = [];
  bool _isLoadingCategories = false;

  @override
  void initState() {
    super.initState();
    
    // Set amount immediately
    if (widget.initialCategory != null) {
      _amountController.text = widget.initialCategory!.allocatedAmount.toString();
    }
    
    // Load categories, then parse initial values
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoadingCategories = true;
    });

    try {
      final categories = await ApiService.getCategories(TransactionType.outflow);
      
      setState(() {
        _categories = categories;
        _isLoadingCategories = false;
        
        // NOW parse the initial category after categories are loaded
        if (widget.initialCategory != null) {
          final categoryName = widget.initialCategory!.mainCategory;
          if (categoryName.contains(' - ')) {
            final parts = categoryName.split(' - ');
            final mainCat = parts[0];
            final subCat = parts[1];
            
            // Validate that this main category exists
            if (_categories.any((cat) => cat.mainCategory == mainCat)) {
              _selectedMainCategory = mainCat;
              
              // Validate that this sub-category exists under this main category
              final mainCategory = _categories.firstWhere(
                (cat) => cat.mainCategory == mainCat,
              );
              if (mainCategory.subCategories.contains(subCat)) {
                _selectedSubCategory = subCat;
              }
            }
          } else {
            // Just a main category
            if (_categories.any((cat) => cat.mainCategory == categoryName)) {
              _selectedMainCategory = categoryName;
              _selectedSubCategory = null;
            }
          }
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingCategories = false;
      });
      print("Error loading categories: $e");
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.initialCategory == null
            ? 'Add Category Budget'
            : 'Edit Category Budget',
        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main Category Dropdown
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: _isLoadingCategories
                    ? Container(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF667eea),
                            ),
                          ),
                        ),
                      )
                    : DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          hintText: 'Select main category',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          prefixIcon: Icon(
                            Icons.category,
                            color: Color(0xFF667eea),
                          ),
                        ),
                        isExpanded: true,
                        value: _selectedMainCategory,
                        items: _categories.map((category) {
                          return DropdownMenuItem(
                            value: category.mainCategory,
                            child: Text(
                              category.mainCategory,
                              style: GoogleFonts.poppins(fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedMainCategory = value;
                            _selectedSubCategory = null; // Reset sub-category
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select a main category';
                          }
                          return null;
                        },
                      ),
              ),

              // Sub Category Dropdown (Optional)
              if (_selectedMainCategory != null && !_isLoadingCategories) ...[
                SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButtonFormField<String?>(
                    decoration: InputDecoration(
                      hintText: 'Sub category (optional)',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      prefixIcon: Icon(
                        Icons.list_outlined,
                        color: Color(0xFF667eea),
                      ),
                    ),
                    isExpanded: true,
                    value: _selectedSubCategory,
                    items: [
                      // Add "All" option for optional sub-category selection
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'All (no filter)',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Add actual sub-categories for the selected main category
                      ..._categories
                          .firstWhere(
                            (cat) => cat.mainCategory == _selectedMainCategory,
                            orElse: () =>
                                Category(mainCategory: '', subCategories: []),
                          )
                          .subCategories
                          .map((subCategory) {
                            return DropdownMenuItem<String?>(
                              value: subCategory,
                              child: Text(
                                subCategory,
                                style: GoogleFonts.poppins(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          })
                          .toList(),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedSubCategory = value;
                      });
                    },
                  ),
                ),
              ],

              SizedBox(height: 16),

              // Amount Field
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Budget Amount',
                  hintText: '0.00',
                  prefixIcon: Icon(
                    Icons.attach_money,
                    color: Color(0xFF667eea),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xFF667eea), width: 2),
                  ),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter amount';
                  }
                  if (double.tryParse(value) == null ||
                      double.parse(value) <= 0) {
                    return 'Please enter valid amount';
                  }
                  return null;
                },
              ),

              // Info text about sub-categories
              if (_selectedMainCategory != null) ...[
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFF667eea).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Color(0xFF667eea),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedSubCategory == null
                              ? 'Budget will track all sub-categories in $_selectedMainCategory'
                              : 'Budget will only track $_selectedSubCategory',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Color(0xFF667eea),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
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
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              // Create display name based on selections
              String displayName = _selectedMainCategory!;
              if (_selectedSubCategory != null) {
                displayName += ' - $_selectedSubCategory';
              }

              // Validate for duplicates
              final createParent = context
                  .findAncestorStateOfType<_CreateBudgetScreenState>();
              
              
              String? error;
              if (createParent != null) {
                error = createParent._validateDuplicateCategory(
                  _selectedMainCategory!,
                  _selectedSubCategory,
                );
              } 
              
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(error, style: GoogleFonts.poppins()),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              widget.onAdd(
                CategoryBudget(
                  mainCategory: displayName,
                  allocatedAmount: double.parse(_amountController.text),
                  spentAmount: 0,
                  percentageUsed: 0,
                  isExceeded: false,
                ),
              );
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF667eea),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(
            'Save',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}