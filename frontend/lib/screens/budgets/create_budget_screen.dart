import 'package:flutter/material.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/budget.dart';
import '../../providers/budget_provider.dart';
import 'ai_budget_suggestion_screen.dart';
import 'package:frontend/services/responsive_helper.dart';

class CreateBudgetScreen extends StatefulWidget {
  @override
  _CreateBudgetScreenState createState() => _CreateBudgetScreenState();
}

class _CreateBudgetScreenState extends State<CreateBudgetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contextController = TextEditingController();

  BudgetPeriod _selectedPeriod = BudgetPeriod.monthly;
  DateTime _startDate = DateTime.now().toUtc();
  DateTime? _endDate;
  List<CategoryBudget> _categoryBudgets = [];

  bool _isLoading = false;
  bool _autoCreateEnabled = false;
  bool _autoCreateWithAi = false;
  bool _showAiFeatures = false;
  Currency _selectedCurrency = Currency.usd;

  final formatter = NumberFormat("#,##0.00", "en_US");

  @override
  void initState() {
    super.initState();
    // Initialize dates based on the default period (Monthly)
    _updateDatesForPeriod(_selectedPeriod);

    // Set default currency from user's preference
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
    _contextController.dispose();
    super.dispose();
  }

  /// Sets the Start and End dates to the "Current" period range based on Today.
  void _updateDatesForPeriod(BudgetPeriod period) {
    final now = DateTime.now().toUtc();
    // Normalize today to start of day (00:00:00)
    final todayStart = DateTime.utc(now.year, now.month, now.day);

    DateTime newStart;
    DateTime newEnd;

    switch (period) {
      case BudgetPeriod.weekly:
        // Start of current week (Monday)
        // DateTime.weekday: Monday=1, Sunday=7
        final daysToSubtract = now.weekday - 1;
        newStart = todayStart.subtract(Duration(days: daysToSubtract));

        // End is Sunday (Start + 6 days) at 23:59:59
        newEnd = newStart.add(
          Duration(
            days: 6,
            hours: 23,
            minutes: 59,
            seconds: 59,
            milliseconds: 999,
          ),
        );
        break;

      case BudgetPeriod.monthly:
        // Start of current month (1st day)
        newStart = DateTime.utc(now.year, now.month, 1);

        // End of current month (Last day)
        final startOfNextMonth = DateTime.utc(now.year, now.month + 1, 1);
        newEnd = startOfNextMonth.subtract(Duration(milliseconds: 1));
        break;

      case BudgetPeriod.yearly:
        // Start of current year (Jan 1st)
        newStart = DateTime.utc(now.year, 1, 1);

        // End of current year (Dec 31st)
        newEnd = DateTime.utc(now.year, 12, 31, 23, 59, 59, 999);
        break;

      case BudgetPeriod.custom:
        // Keep existing dates or default if null
        newStart = _startDate;
        newEnd = _endDate ?? _startDate.add(Duration(days: 30));
        break;
    }

    setState(() {
      _selectedPeriod = period;
      _startDate = newStart;
      _endDate = newEnd;
    });
  }

  /// Recalculates the End Date based on the current _startDate and _selectedPeriod.
  /// This is used when the user changes start date but keeps the Period type (if aligned).
  void _recalculateEndDateForStandardPeriod() {
    switch (_selectedPeriod) {
      case BudgetPeriod.weekly:
        // End is 6 days after start
        _endDate = _startDate.add(
          Duration(
            days: 6,
            hours: 23,
            minutes: 59,
            seconds: 59,
            milliseconds: 999,
          ),
        );
        break;

      case BudgetPeriod.monthly:
        // End is last day of the started month
        final nextMonth = DateTime.utc(
          _startDate.year,
          _startDate.month + 1,
          1,
        );
        _endDate = nextMonth.subtract(Duration(milliseconds: 1));
        break;

      case BudgetPeriod.yearly:
        // End is Dec 31st of the started year
        _endDate = DateTime.utc(_startDate.year, 12, 31, 23, 59, 59, 999);
        break;

      case BudgetPeriod.custom:
        // Do nothing automatically for custom
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
      // Set start date to beginning of day in UTC
      final newStart = DateTime.utc(
        picked.year,
        picked.month,
        picked.day,
        0,
        0,
        0,
      );

      setState(() {
        _startDate = newStart;

        // CHECK ALIGNMENT:
        // If the user picked a date that doesn't fit the standard definition
        // of the selected period, switch to Custom.
        bool shouldSwitchToCustom = false;

        if (_selectedPeriod != BudgetPeriod.custom) {
          switch (_selectedPeriod) {
            case BudgetPeriod.weekly:
              // Must be a Monday (1)
              if (newStart.weekday != 1) shouldSwitchToCustom = true;
              break;
            case BudgetPeriod.monthly:
              // Must be the 1st of the month
              if (newStart.day != 1) shouldSwitchToCustom = true;
              break;
            case BudgetPeriod.yearly:
              // Must be Jan 1st
              if (newStart.month != 1 || newStart.day != 1)
                shouldSwitchToCustom = true;
              break;
            default:
              break;
          }

          if (shouldSwitchToCustom) {
            _selectedPeriod = BudgetPeriod.custom;
            // Ensure end date is valid (after start date)
            if (_endDate != null && _endDate!.isBefore(_startDate)) {
              _endDate = _startDate.add(Duration(days: 30));
            } else if (_endDate == null) {
              _endDate = _startDate.add(Duration(days: 30));
            }
          } else {
            // It aligns (e.g., user picked 1st of NEXT month for a Monthly budget),
            // so we keep the period type but update the end date.
            _recalculateEndDateForStandardPeriod();
          }
        } else {
          // Already custom, just ensure end date validity
          if (_endDate != null && _endDate!.isBefore(_startDate)) {
            _endDate = _startDate.add(Duration(days: 1)); // Default to next day
          }
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
    final localizations = AppLocalizations.of(context);
    for (var existingCat in _categoryBudgets) {
      String existingMain = existingCat.mainCategory;
      String? existingSubStr;

      if (existingMain.contains(' - ')) {
        final parts = existingMain.split(' - ');
        existingMain = parts[0];
        existingSubStr = parts[1];
      }

      if (existingMain == mainCategory) {
        if ((subCategory == null || subCategory == 'All') &&
            existingSubStr == null) {
          return localizations.createYourFirstBudget;
        }
        if (subCategory != null &&
            subCategory != 'All' &&
            existingSubStr == subCategory) {
          return localizations.createYourFirstBudget;
        }
      }
    }
    return null;
  }

  double _calculateTotalBudget() {
    Set<String> mainCategories = {};
    List<MapEntry<String, double>> subCategories = [];

    for (var cat in _categoryBudgets) {
      if (cat.mainCategory.contains(' - ')) {
        final parts = cat.mainCategory.split(' - ');
        subCategories.add(MapEntry(parts[0], cat.allocatedAmount));
      } else {
        mainCategories.add(cat.mainCategory);
      }
    }

    double total = 0.0;

    for (var cat in _categoryBudgets) {
      if (!cat.mainCategory.contains(' - ')) {
        total += cat.allocatedAmount;
      }
    }

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
    final localizations = AppLocalizations.of(context);

    if (!authProvider.isPremium) {
      Navigator.pushNamed(context, '/subscription');
      return;
    }

    if (_selectedPeriod == BudgetPeriod.custom && _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.selectEndDate),
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
          currency: _selectedCurrency,
        ),
      ),
    );

    if (result != null && result is AIBudgetSuggestion) {
      setState(() {
        _nameController.text = result.suggestedName;
        _categoryBudgets = result.categoryBudgets;
      });
    }
  }

  Future<void> _saveBudget() async {
    final localizations = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;

    if (_categoryBudgets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.addOneCategoryBudget),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedPeriod == BudgetPeriod.custom && _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.addOneCategoryBudget),
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
          currency: _selectedCurrency,
        );

    setState(() => _isLoading = false);

    if (success) {
      Navigator.pop(context, true);
    } else {
      final error = Provider.of<BudgetProvider>(context, listen: false).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? localizations.failedToCreateBudget),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // NOTE: Removed _calculateEndDate() from build method to avoid side effects.
    // Date calculation is now handled in event handlers.

    final totalBudget = _calculateTotalBudget();
    final authProvider = Provider.of<AuthProvider>(context);
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);


    return Scaffold(
      appBar: AppBar(
        title: Text(
          localizations.createBudget,
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
            colors: [Color(0xFF667eea).withOpacity(0.1), Colors.white],
          ),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: responsive.padding(all: 20),
            children: [
              // Currency Selector
              Text(
                localizations.currency,
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                ),
              ),
              SizedBox(height: responsive.sp8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(
                    responsive.borderRadius(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 2,
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: DropdownButtonFormField<Currency>(
                  isExpanded: true,
                  decoration: InputDecoration(
                    hintText: localizations.selectCurrency,
                    border: InputBorder.none,
                    contentPadding: responsive.padding(all: 15),
                    prefixIcon: Icon(
                      Icons.attach_money,
                      color: Color(0xFF667eea),
                    ),
                  ),
                  value: _selectedCurrency,
                  items: Currency.values.map((currency) {
                    return DropdownMenuItem(
                      value: currency,
                      child: Text(
                        '${currency.symbol} - ${currency.displayName}',
                        style: GoogleFonts.poppins(fontSize: responsive.fs14),
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
                      return localizations.pleaseSelectCurrency;
                    }
                    return null;
                  },
                ),
              ),
              SizedBox(height: responsive.sp12),

              Container(
                padding: responsive.padding(all: 12),
                decoration: BoxDecoration(
                  color: Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(
                    responsive.borderRadius(12),
                  ),
                  border: Border.all(color: Color(0xFF2196F3).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Color(0xFF2196F3),
                      size: responsive.icon20,
                    ),
                    SizedBox(width: responsive.sp8),
                    Expanded(
                      child: Text(
                        'Only transactions in ${_selectedCurrency.displayName} will affect this budget',
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs12,
                          color: Color(0xFF2196F3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: responsive.sp24),

              // Collapsible AI Features Section
              Container(
                margin: EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(
                    responsive.borderRadius(12),
                  ),
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
                    InkWell(
                      onTap: () {
                        setState(() {
                          _showAiFeatures = !_showAiFeatures;
                        });
                      },
                      borderRadius: BorderRadius.circular(
                        responsive.borderRadius(12),
                      ),
                      child: Container(
                        padding: responsive.padding(all: 16),
                        child: Row(
                          children: [
                            Container(
                              padding: responsive.padding(all: 8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF667eea).withOpacity(0.2),
                                    Color(0xFF764ba2).withOpacity(0.2),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(
                                  responsive.borderRadius(8),
                                ),
                              ),
                              child: Icon(
                                Icons.auto_awesome,
                                color: Color(0xFF667eea),
                                size: responsive.icon24,
                              ),
                            ),
                            SizedBox(width: responsive.sp12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        localizations.aiFeatures,
                                        style: GoogleFonts.poppins(
                                          fontSize: responsive.fs16,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF333333),
                                        ),
                                      ),
                                      SizedBox(width: responsive.sp8),
                                      if (!authProvider.isPremium)
                                        Icon(
                                          Icons.lock,
                                          size: responsive.icon16,
                                          color: Color(0xFFFFD700),
                                        ),
                                      SizedBox(width: responsive.sp8),
                                      if (!authProvider.isPremium)
                                        Container(
                                          padding: responsive.padding(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Color(
                                              0xFFFFD700,
                                            ).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(
                                              responsive.borderRadius(8),
                                            ),
                                            border: Border.all(
                                              color: Color(0xFFFFD700),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            localizations.premium,
                                            style: GoogleFonts.poppins(
                                              fontSize: responsive.fs10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFFFD700),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  Text(
                                    _showAiFeatures
                                        ? localizations
                                              .getAiPoweredBudgetSuggestions
                                        : localizations
                                              .tapToUseAiBudgetSuggestions,
                                    style: GoogleFonts.poppins(
                                      fontSize: responsive.fs12,
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

                    if (_showAiFeatures) ...[
                      Divider(height: 1),
                      Padding(
                        padding: responsive.padding(all: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: responsive.padding(all: 16),
                              decoration: BoxDecoration(
                                color: Color(0xFF667eea).withOpacity(0.05),
                                borderRadius: BorderRadius.circular(
                                  responsive.borderRadius(12),
                                ),
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
                                        size: responsive.icon18,
                                      ),
                                      SizedBox(width: responsive.sp8),
                                      Text(
                                        localizations.context,
                                        style: GoogleFonts.poppins(
                                          fontSize: responsive.fs14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF333333),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: responsive.sp8),
                                  Text(
                                    localizations.addContext,
                                    style: GoogleFonts.poppins(
                                      fontSize: responsive.fs12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  SizedBox(height: responsive.sp12),
                                  TextFormField(
                                    controller: _contextController,
                                    decoration: InputDecoration(
                                      hintText: localizations
                                          .egTravelingHolidaySeason,
                                      hintStyle: GoogleFonts.poppins(
                                        fontSize: responsive.fs12,
                                        color: Colors.grey[400],
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                          responsive.borderRadius(12),
                                        ),
                                        borderSide: BorderSide(
                                          color: Colors.grey[300]!,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                          responsive.borderRadius(12),
                                        ),
                                        borderSide: BorderSide(
                                          color: Colors.grey[300]!,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                          responsive.borderRadius(12),
                                        ),
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

                            SizedBox(height: responsive.sp16),

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _navigateToAISuggestion,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF667eea),
                                  padding: responsive.padding(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      responsive.borderRadius(12),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome,
                                      color: Colors.white,
                                      size: responsive.icon20,
                                    ),
                                    SizedBox(width: responsive.sp8),
                                    Text(
                                      localizations.generateAiBudget,
                                      style: GoogleFonts.poppins(
                                        fontSize: responsive.fs14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            SizedBox(height: responsive.sp8),

                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: responsive.icon16,
                                  color: Color(0xFF667eea),
                                ),
                                SizedBox(width: responsive.sp4),
                                Expanded(
                                  child: Text(
                                    localizations
                                        .aiWillAnalyzeAndSuggestBudgets,
                                    style: GoogleFonts.poppins(
                                      fontSize: responsive.fs11,
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
                  labelText: localizations.budgetName,
                  hintText: localizations.egMonthlyExpenses,
                  prefixIcon: Icon(Icons.label, color: Color(0xFF667eea)),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return localizations.enterBudgetName;
                  }
                  return null;
                },
              ),

              SizedBox(height: responsive.sp16),

              // Period Selector
              Text(
                localizations.budgetPeriod,
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                ),
              ),
              SizedBox(height: responsive.sp8),
              Container(
                padding: responsive.padding(all: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(
                    responsive.borderRadius(12),
                  ),
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
                    _buildPeriodButton(localizations.week, BudgetPeriod.weekly),
                    _buildPeriodButton(
                      localizations.month,
                      BudgetPeriod.monthly,
                    ),
                    _buildPeriodButton(localizations.year, BudgetPeriod.yearly),
                    _buildPeriodButton(
                      localizations.custom,
                      BudgetPeriod.custom,
                    ),
                  ],
                ),
              ),

              SizedBox(height: responsive.sp16),

              // Date Selection
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectStartDate,
                      child: Container(
                        padding: responsive.padding(all: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            responsive.borderRadius(12),
                          ),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizations.startDate,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs10,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: responsive.sp4),
                            Text(
                              DateFormat('MMM d, yyyy').format(_startDate),
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: responsive.sp12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectedPeriod == BudgetPeriod.custom
                          ? _selectEndDate
                          : null,
                      child: Container(
                        padding: responsive.padding(all: 12),
                        decoration: BoxDecoration(
                          color: _selectedPeriod == BudgetPeriod.custom
                              ? Colors.white
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(
                            responsive.borderRadius(12),
                          ),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizations.endDateNoOp,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs10,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: responsive.sp4),
                            Text(
                              _endDate != null
                                  ? DateFormat('MMM d, yyyy').format(_endDate!)
                                  : localizations.auto,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs14,
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

              SizedBox(height: responsive.sp16),

              // Description Field
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: localizations.descriptionLabel,
                  hintText: localizations.notesThisBudget,
                  prefixIcon: Icon(Icons.note, color: Color(0xFF667eea)),
                ),
                maxLines: 2,
              ),

              SizedBox(height: responsive.sp24),

              if (_selectedPeriod != BudgetPeriod.custom) ...[
                SizedBox(height: responsive.sp24),
                Container(
                  padding: responsive.padding(all: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF667eea).withOpacity(0.1),
                        Color(0xFF764ba2).withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(
                      responsive.borderRadius(12),
                    ),
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
                          SizedBox(width: responsive.sp8),
                          Expanded(
                            child: Text(
                              localizations.autoCreateNextBudget,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: responsive.sp8),
                      Text(
                        localizations.automaticallyCreateNewBudget,
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs12,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: responsive.sp12),
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
                          localizations.enableAutoCreate,
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        activeColor: Color(0xFF667eea),
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_autoCreateEnabled) ...[
                        Divider(),
                        Text(
                          localizations.chooseHowToCreateNextBudget,
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF333333),
                          ),
                        ),
                        SizedBox(height: responsive.sp8),
                        RadioListTile<bool>(
                          value: false,
                          groupValue: _autoCreateWithAi,
                          onChanged: (value) {
                            setState(() {
                              _autoCreateWithAi = value!;
                            });
                          },
                          title: Text(
                            localizations.useCurrentCategories,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs13,
                            ),
                          ),
                          subtitle: Text(
                            localizations.keepTheSameBudgetAmounts,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs11,
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
                                size: responsive.icon16,
                                color: Color(0xFF667eea),
                              ),
                              SizedBox(width: responsive.sp4),
                              Expanded(
                                child: Text(
                                  localizations.aiOptimizedBudget,
                                  style: GoogleFonts.poppins(
                                    fontSize: responsive.fs13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            localizations.aiAnalyzesSpendingAndSuggestsAmounts,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs11,
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

              SizedBox(height: responsive.sp24),

              // Category Budgets Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    localizations.categoryBudgets,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addCategoryBudget,
                    icon: Icon(Icons.add_circle, color: Color(0xFF667eea)),
                    label: Text(
                      localizations.add,
                      style: GoogleFonts.poppins(color: Color(0xFF667eea)),
                    ),
                  ),
                ],
              ),

              SizedBox(height: responsive.sp12),

              if (_categoryBudgets.isEmpty)
                Container(
                  padding: responsive.padding(all: 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(
                      responsive.borderRadius(12),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      localizations.noCategoriesAddedYet,
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

              SizedBox(height: responsive.sp24),

              // Total Budget Display
              Container(
                padding: responsive.padding(all: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  ),
                  borderRadius: BorderRadius.circular(
                    responsive.borderRadius(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      localizations.totalBudget,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${_selectedCurrency.symbol}${formatter.format(totalBudget)}', // Changed
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: responsive.sp24),

              // Save Button
              SizedBox(
                height: responsive.cardHeight(baseHeight: 50),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveBudget,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF667eea),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        responsive.borderRadius(12),
                      ),
                    ),
                  ),
                  child: _isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text(
                          localizations.createBudget,
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
    );
  }

  Widget _buildPeriodButton(String label, BudgetPeriod period) {
    bool isSelected = _selectedPeriod == period;
    final responsive = ResponsiveHelper(context);
    return Expanded(
      child: GestureDetector(
        onTap: () {
          // Updates dates to the current period start/end when tapped
          _updateDatesForPeriod(period);
        },
        child: Container(
          padding: responsive.padding(vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(colors: [Color(0xFF667eea), Color(0xFF764ba2)])
                : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: responsive.fs12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBudgetCard(CategoryBudget catBudget, int index) {
    final responsive = ResponsiveHelper(context);
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
      ),
      child: Row(
        children: [
          Container(
            width: responsive.iconSize(mobile: 40),
            height: responsive.iconSize(mobile: 40),
            decoration: BoxDecoration(
              color: Color(0xFF667eea).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.category,
              color: Color(0xFF667eea),
              size: responsive.icon20,
            ),
          ),
          SizedBox(width: responsive.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  catBudget.mainCategory,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                Text(
                  '\$${formatter.format(catBudget.allocatedAmount)}', // Changed
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.edit,
              color: Color(0xFF667eea),
              size: responsive.icon20,
            ),
            onPressed: () => _editCategoryBudget(index),
          ),
          IconButton(
            icon: Icon(
              Icons.delete,
              color: Colors.red,
              size: responsive.icon20,
            ),
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

  _AddCategoryDialog({this.initialCategory, required this.onAdd});

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
      _amountController.text = widget.initialCategory!.allocatedAmount
          .toString();
    }

    // Load categories, then parse initial values
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoadingCategories = true;
    });

    try {
      final categories = await ApiService.getCategories(
        TransactionType.outflow,
      );

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
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
      ),
      title: Text(
        widget.initialCategory == null
            ? localizations.addCategoryBudget
            : localizations.editCategoryBudget,
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
                  borderRadius: BorderRadius.circular(
                    responsive.borderRadius(12),
                  ),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: _isLoadingCategories
                    ? Container(
                        padding: responsive.padding(all: 20),
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
                          hintText: localizations.selectMainCategoryHint,
                          border: InputBorder.none,
                          contentPadding: responsive.padding(
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
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs14,
                              ),
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
                            return localizations.validationMainCategoryRequired;
                          }
                          return null;
                        },
                      ),
              ),

              // Sub Category Dropdown (Optional)
              if (_selectedMainCategory != null && !_isLoadingCategories) ...[
                SizedBox(height: responsive.sp16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(
                      responsive.borderRadius(12),
                    ),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButtonFormField<String?>(
                    decoration: InputDecoration(
                      hintText: localizations.subCategory,
                      border: InputBorder.none,
                      contentPadding: responsive.padding(
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
                          localizations.allNoFilter,
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs14,
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
                                style: GoogleFonts.poppins(
                                  fontSize: responsive.fs14,
                                ),
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

              SizedBox(height: responsive.sp16),

              // Amount Field
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: localizations.budgetAmount,
                  hintText: '0.00',
                  prefixIcon: Icon(
                    Icons.attach_money,
                    color: Color(0xFF667eea),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      responsive.borderRadius(12),
                    ),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      responsive.borderRadius(12),
                    ),
                    borderSide: BorderSide(color: Color(0xFF667eea), width: 2),
                  ),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return localizations.enterAmount;
                  }
                  if (double.tryParse(value) == null ||
                      double.parse(value) <= 0) {
                    return localizations.enterValidAmount;
                  }
                  return null;
                },
              ),

              // Info text about sub-categories
              if (_selectedMainCategory != null) ...[
                SizedBox(height: responsive.sp12),
                Container(
                  padding: responsive.padding(all: 12),
                  decoration: BoxDecoration(
                    color: Color(0xFF667eea).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(
                      responsive.borderRadius(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: responsive.icon16,
                        color: Color(0xFF667eea),
                      ),
                      SizedBox(width: responsive.sp8),
                      Expanded(
                        child: Text(
                          _selectedSubCategory == null
                              ? 'Budget will track all sub-categories in $_selectedMainCategory'
                              : 'Budget will only track $_selectedSubCategory',
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs11,
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
            localizations.dialogCancel,
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
              borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
            ),
            padding: responsive.padding(horizontal: 24, vertical: 12),
          ),
          child: Text(
            localizations.save,
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
