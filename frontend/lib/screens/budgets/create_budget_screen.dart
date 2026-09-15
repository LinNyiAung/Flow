import 'package:flutter/material.dart';
import 'package:frontend/models/transaction.dart' hide formatter;
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/category_icons.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/hero_card.dart';
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
  final _contextController = TextEditingController();

  BudgetPeriod _selectedPeriod = BudgetPeriod.monthly;
  DateTime _startDate = DateTime.now().toUtc();
  DateTime? _endDate;
  List<CategoryBudget> _categoryBudgets = [];

  bool _isLoading = false;
  bool _autoCreateEnabled = false;
  bool _autoCreateWithAi = false;
  Currency _selectedCurrency = Currency.usd;

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
    final scheme = Theme.of(context).colorScheme;
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: scheme.primary),
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
    final scheme = Theme.of(context).colorScheme;
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(Duration(days: 30)),
      firstDate: _startDate,
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: scheme.primary),
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
          return localizations.categoryAlreadyExists;
        }
        if (subCategory != null &&
            subCategory != 'All' &&
            existingSubStr == subCategory) {
          return localizations.categoryAlreadyExists;
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
    showAppBottomSheet<void>(
      context: context,
      builder: (context) => _CategoryCapSheet(
        title: AppLocalizations.of(context).addCategoryBudget,
        validateDuplicate: _validateDuplicateCategory,
        onSave: (categoryBudget) {
          setState(() {
            _categoryBudgets.add(categoryBudget);
          });
        },
      ),
    );
  }

  void _editCategoryBudget(int index) {
    showAppBottomSheet<void>(
      context: context,
      builder: (context) => _CategoryCapSheet(
        title: AppLocalizations.of(context).editCategoryBudget,
        initialCategory: _categoryBudgets[index],
        validateDuplicate: _validateDuplicateCategory,
        onSave: (categoryBudget) {
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
        SnackBar(content: Text(localizations.selectEndDate)),
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
        SnackBar(content: Text(localizations.addOneCategoryBudget)),
      );
      return;
    }

    if (_selectedPeriod == BudgetPeriod.custom && _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.addOneCategoryBudget)),
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
        SnackBar(content: Text(error ?? localizations.failedToCreateBudget)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalBudget = _calculateTotalBudget();
    final authProvider = Provider.of<AuthProvider>(context);
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.createBudget),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: GestureDetector(
                onTap: _isLoading ? null : _saveBudget,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: _isLoading ? scheme.outline : scheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          localizations.createBudget,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            // AI entry point
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: scheme.tertiary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          localizations.getAiPoweredBudgetSuggestions,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onTertiaryContainer),
                        ),
                      ),
                      if (!authProvider.isPremium) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.lock_rounded, size: 16, color: scheme.tertiary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    localizations.aiWillAnalyzeAndSuggestBudgets,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onTertiaryContainer, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _contextController,
                    decoration: InputDecoration(
                      hintText: localizations.egTravelingHolidaySeason,
                      filled: true,
                      // Mockup's --warn-field (FFFDF6 light / 2A2618 dark) —
                      // plain white reads wrong against the gold container
                      // in dark mode.
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF2A2618)
                          : const Color(0xFFFFFDF6),
                      isDense: true,
                      prefixIcon: Icon(Icons.note_alt_rounded, color: scheme.tertiary),
                      counterText: '',
                    ),
                    maxLines: 2,
                    maxLength: 200,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _navigateToAISuggestion,
                      style: FilledButton.styleFrom(backgroundColor: scheme.tertiary),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text(localizations.generateAiBudget),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Name Field
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: localizations.budgetName,
                hintText: localizations.egMonthlyExpenses,
                prefixIcon: const Icon(Icons.label_outline_rounded),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return localizations.enterBudgetName;
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            // Currency Selector
            Text(localizations.currency, style: _sectionLabelStyle(context)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final currency in Currency.values) ...[
                  _currencyChip(currency),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${localizations.onlyTransactionsInPrefix} ${_selectedCurrency.displayName} ${localizations.willAffectThisBudgetSuffix}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
            ),

            const SizedBox(height: 20),

            // Period Selector
            Text(localizations.budgetPeriod, style: _sectionLabelStyle(context)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: AppTheme.trackFor(context), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  _periodSegment(localizations.week, BudgetPeriod.weekly),
                  _periodSegment(localizations.month, BudgetPeriod.monthly),
                  _periodSegment(localizations.year, BudgetPeriod.yearly),
                  _periodSegment(localizations.custom, BudgetPeriod.custom),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Date Selection
            Row(
              children: [
                Expanded(
                  child: _dateCard(
                    label: localizations.startDate,
                    value: DateFormat('MMM d, yyyy').format(_startDate),
                    onTap: _selectStartDate,
                    enabled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dateCard(
                    label: localizations.endDateNoOp,
                    value: _endDate != null
                        ? DateFormat('MMM d, yyyy').format(_endDate!)
                        : localizations.auto,
                    onTap: _selectEndDate,
                    enabled: _selectedPeriod == BudgetPeriod.custom,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Description Field
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: localizations.descriptionLabel,
                hintText: localizations.notesThisBudget,
                prefixIcon: const Icon(Icons.notes_rounded),
              ),
              maxLines: 2,
            ),

            if (_selectedPeriod != BudgetPeriod.custom) ...[
              const SizedBox(height: 24),
              _buildAutoCreateCard(localizations),
            ],

            const SizedBox(height: 24),

            // Category Budgets Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(localizations.categoryBudgets, style: _sectionLabelStyle(context)),
                TextButton.icon(
                  onPressed: _addCategoryBudget,
                  icon: const Icon(Icons.add_circle_rounded, size: 18),
                  label: Text(localizations.add),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_categoryBudgets.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outline, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    localizations.noCategoriesAddedYet,
                    style: TextStyle(color: AppTheme.hintFor(context)),
                  ),
                ),
              )
            else ...[
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Theme.of(context).cardTheme.shadowColor ?? const Color(0x14101815), blurRadius: 8, offset: Offset(0, 1)),
                  ],
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < _categoryBudgets.length; i++)
                      _buildCategoryBudgetRow(_categoryBudgets[i], i, isFirst: i == 0),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              HeroCard(label: localizations.totalBudget, value: '${_selectedCurrency.symbol}${formatter.format(totalBudget)}'),
            ],
          ],
        ),
      ),
    );
  }

  TextStyle _sectionLabelStyle(BuildContext context) => TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant);

  Widget _currencyChip(Currency currency) {
    final selected = _selectedCurrency == currency;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => setState(() => _selectedCurrency = currency),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? scheme.primary : scheme.outline),
        ),
        child: Text(
          '${currency.symbol} ${currency.name.toUpperCase()}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _periodSegment(String label, BudgetPeriod period) {
    final isSelected = _selectedPeriod == period;
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: () => _updateDatesForPeriod(period),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateCard({
    required String label,
    required String value,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: enabled ? Theme.of(context).cardTheme.color : scheme.outlineVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface)),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoCreateCard(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Theme.of(context).cardTheme.shadowColor ?? const Color(0x14101815), blurRadius: 8, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.autorenew_rounded, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(localizations.autoCreateNextBudget, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      localizations.automaticallyCreateNewBudget,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _autoCreateEnabled,
                onChanged: (value) {
                  setState(() {
                    _autoCreateEnabled = value;
                    if (!value) {
                      _autoCreateWithAi = false;
                    }
                  });
                },
              ),
            ],
          ),
          if (_autoCreateEnabled) ...[
            const SizedBox(height: 10),
            _autoOptionCard(
              selected: !_autoCreateWithAi,
              title: localizations.useCurrentCategories,
              subtitle: localizations.keepTheSameBudgetAmounts,
              onTap: () => setState(() => _autoCreateWithAi = false),
            ),
            const SizedBox(height: 8),
            _autoOptionCard(
              selected: _autoCreateWithAi,
              title: localizations.aiOptimizedBudget,
              subtitle: localizations.aiAnalyzesSpendingAndSuggestsAmounts,
              icon: Icons.auto_awesome_rounded,
              onTap: () => setState(() => _autoCreateWithAi = true),
            ),
          ],
        ],
      ),
    );
  }

  Widget _autoOptionCard({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? scheme.primary : scheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: scheme.tertiary),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBudgetRow(CategoryBudget catBudget, int index, {required bool isFirst}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: isFirst ? null : Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
              child: Icon(iconForCategoryName(catBudget.mainCategory), color: scheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            // Name gets its own full-width line instead of sharing one with
            // the amount — the two were fighting for space and the name
            // (often longer, e.g. "Housing & Utilities") lost, truncating
            // to "Housing & Uti…" even at a readable screen width.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    catBudget.mainCategory,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_selectedCurrency.symbol}${formatter.format(catBudget.allocatedAmount)}',
                    style: AppTheme.money(14, weight: FontWeight.w700, color: scheme.primary),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.edit_rounded, size: 18, color: scheme.primary),
              onPressed: () => _editCategoryBudget(index),
            ),
            IconButton(
              icon: Icon(Icons.delete_rounded, size: 20, color: scheme.error),
              onPressed: () => _removeCategoryBudget(index),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for adding or editing a single category cap. Shared shape
/// used by both the create and edit budget flows.
class _CategoryCapSheet extends StatefulWidget {
  final String title;
  final CategoryBudget? initialCategory;
  final String? Function(String mainCategory, String? subCategory) validateDuplicate;
  final void Function(CategoryBudget) onSave;

  const _CategoryCapSheet({
    required this.title,
    this.initialCategory,
    required this.validateDuplicate,
    required this.onSave,
  });

  @override
  State<_CategoryCapSheet> createState() => _CategoryCapSheetState();
}

class _CategoryCapSheetState extends State<_CategoryCapSheet> {
  final _amountController = TextEditingController();
  String? _selectedMainCategory;
  String? _selectedSubCategory;
  List<Category> _categories = [];
  bool _isLoadingCategories = false;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      _amountController.text = widget.initialCategory!.allocatedAmount.toString();
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoadingCategories = true);

    try {
      final categories = await ApiService.getCategories(TransactionType.outflow);

      setState(() {
        _categories = categories;
        _isLoadingCategories = false;

        if (widget.initialCategory != null) {
          final categoryName = widget.initialCategory!.mainCategory;
          if (categoryName.contains(' - ')) {
            final parts = categoryName.split(' - ');
            final mainCat = parts[0];
            final subCat = parts[1];

            if (_categories.any((cat) => cat.mainCategory == mainCat)) {
              _selectedMainCategory = mainCat;
              final mainCategory = _categories.firstWhere((cat) => cat.mainCategory == mainCat);
              if (mainCategory.subCategories.contains(subCat)) {
                _selectedSubCategory = subCat;
              }
            }
          } else {
            if (_categories.any((cat) => cat.mainCategory == categoryName)) {
              _selectedMainCategory = categoryName;
              _selectedSubCategory = null;
            }
          }
        }
      });
    } catch (e) {
      setState(() => _isLoadingCategories = false);
      print("Error loading categories: $e");
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    final localizations = AppLocalizations.of(context);

    if (_selectedMainCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.validationMainCategoryRequired)),
      );
      return;
    }

    final amountText = _amountController.text;
    final amount = double.tryParse(amountText);
    if (amountText.isEmpty) {
      setState(() => _amountError = localizations.enterAmount);
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _amountError = localizations.enterValidAmount);
      return;
    }
    setState(() => _amountError = null);

    String displayName = _selectedMainCategory!;
    if (_selectedSubCategory != null) {
      displayName += ' - $_selectedSubCategory';
    }

    final error = widget.validateDuplicate(_selectedMainCategory!, _selectedSubCategory);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    widget.onSave(
      CategoryBudget(
        mainCategory: displayName,
        allocatedAmount: amount,
        spentAmount: 0,
        percentageUsed: 0,
        isExceeded: false,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Text(localizations.selectMainCategoryHint, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          if (_isLoadingCategories)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((category) {
                final selected = _selectedMainCategory == category.mainCategory;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedMainCategory = category.mainCategory;
                      _selectedSubCategory = null;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? scheme.primary : Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selected ? scheme.primary : scheme.outline),
                    ),
                    child: Text(
                      category.mainCategory,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          if (_selectedMainCategory != null && !_isLoadingCategories) ...[
            const SizedBox(height: 16),
            Text(localizations.subCategory, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _subCategoryChip(localizations.allNoFilter, null),
                for (final sub in _categories
                    .firstWhere(
                      (cat) => cat.mainCategory == _selectedMainCategory,
                      orElse: () => Category(mainCategory: '', subCategories: []),
                    )
                    .subCategories)
                  _subCategoryChip(sub, sub),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Text(localizations.budgetAmount, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '0.00',
              prefixIcon: const Icon(Icons.attach_money_rounded),
              errorText: _amountError,
            ),
            onChanged: (_) {
              if (_amountError != null) setState(() => _amountError = null);
            },
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              child: Text(localizations.save),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subCategoryChip(String label, String? value) {
    final selected = _selectedSubCategory == value;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => setState(() => _selectedSubCategory = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? scheme.primary : scheme.outline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
