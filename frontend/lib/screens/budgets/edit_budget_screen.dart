import 'package:flutter/material.dart';
import 'package:frontend/models/transaction.dart' hide formatter;
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/category_icons.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/hero_card.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/budget.dart';
import '../../providers/budget_provider.dart';

import '../../services/localization_service.dart';

class EditBudgetScreen extends StatefulWidget {
  final Budget budget;

  EditBudgetScreen({required this.budget});

  @override
  _EditBudgetScreenState createState() => _EditBudgetScreenState();
}

class _EditBudgetScreenState extends State<EditBudgetScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;

  late List<CategoryBudget> _categoryBudgets;
  bool _isLoading = false;

  late bool _autoCreateEnabled;
  late bool _autoCreateWithAi;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.budget.name);
    _descriptionController = TextEditingController(
      text: widget.budget.description ?? '',
    );
    _categoryBudgets = List.from(widget.budget.categoryBudgets);
    _autoCreateEnabled = widget.budget.autoCreateEnabled;
    _autoCreateWithAi = widget.budget.autoCreateWithAi;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String? _validateDuplicateCategory(
    String mainCategory,
    String? subCategory, {
    int? excludeIndex,
  }) {
    final localizations = AppLocalizations.of(context);
    for (int i = 0; i < _categoryBudgets.length; i++) {
      if (excludeIndex != null && i == excludeIndex) continue;

      var existingCat = _categoryBudgets[i];
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

  /// Category caps whose newly-entered allocation is below what has already
  /// been spent against that same category on the live budget.
  List<CategoryBudget> get _categoriesBelowSpent {
    final result = <CategoryBudget>[];
    for (final cat in _categoryBudgets) {
      CategoryBudget? original;
      for (final orig in widget.budget.categoryBudgets) {
        if (orig.mainCategory == cat.mainCategory) {
          original = orig;
          break;
        }
      }
      if (original != null && cat.allocatedAmount < original.spentAmount) {
        result.add(cat);
      }
    }
    return result;
  }

  void _addCategoryBudget() {
    showAppBottomSheet<void>(
      context: context,
      builder: (context) => _CategoryCapSheet(
        title: AppLocalizations.of(context).addCategoryBudget,
        validateDuplicate: (main, sub) => _validateDuplicateCategory(main, sub),
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
        validateDuplicate: (main, sub) =>
            _validateDuplicateCategory(main, sub, excludeIndex: index),
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

  Future<void> _saveBudget() async {
    final localizations = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;

    if (_categoryBudgets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.addOneCategoryBudget)),
      );
      return;
    }

    setState(() => _isLoading = true);

    final totalBudget = _calculateTotalBudget();

    final success = await Provider.of<BudgetProvider>(context, listen: false)
        .updateBudget(
          budgetId: widget.budget.id,
          name: _nameController.text,
          categoryBudgets: _categoryBudgets,
          totalBudget: totalBudget,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          autoCreateEnabled: _autoCreateEnabled,
          autoCreateWithAi: _autoCreateWithAi,
        );

    setState(() => _isLoading = false);

    if (success) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.budgetUpdatedSuccessfully)),
      );
    } else {
      final error = Provider.of<BudgetProvider>(context, listen: false).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? localizations.failedToUpdateBudget)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalBudget = _calculateTotalBudget();
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final belowSpent = _categoriesBelowSpent;

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.editBudget),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
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
                          localizations.save,
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
            // Locked period + currency
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _tintNeutral(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_rounded, size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        'FIXED FOR THIS BUDGET',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _lockedField(
                          localizations.period,
                          widget.budget.period.name.toUpperCase(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _lockedField(
                          localizations.duration,
                          '${DateFormat('MMM d').format(widget.budget.startDate)} - ${DateFormat('MMM d, yyyy').format(widget.budget.endDate)}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _lockedField(
                    localizations.currencyC,
                    '${widget.budget.currency.symbol}  ${widget.budget.currency.displayName}',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Period and currency can't change once a budget has spending against it — create a new budget instead.",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Name Field
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: localizations.budgetName,
                prefixIcon: const Icon(Icons.label_outline_rounded),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return localizations.enterBudgetName;
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Description Field
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: localizations.descriptionLabel,
                prefixIcon: const Icon(Icons.notes_rounded),
              ),
              maxLines: 2,
            ),

            if (widget.budget.period != BudgetPeriod.custom) ...[
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

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: scheme.tertiary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      localizations.editingCategoriesRecalculateAlert,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: scheme.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

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
            else
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

            if (belowSpent.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_rounded, color: scheme.error, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'This cap is already spent',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onErrorContainer),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${belowSpent.map((c) => c.mainCategory).join(', ')} ${belowSpent.length > 1 ? 'already have' : 'already has'} more spent than the new cap allows.',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onErrorContainer, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (totalBudget != widget.budget.totalBudget) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL CAP',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          '${widget.budget.currency.symbol}${formatter.format(widget.budget.totalBudget)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.arrow_forward_rounded, size: 20, color: scheme.onPrimaryContainer),
                        const SizedBox(width: 12),
                        Text(
                          '${widget.budget.currency.symbol}${formatter.format(totalBudget)}',
                          style: AppTheme.money(24, weight: FontWeight.w800, color: scheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          totalBudget > widget.budget.totalBudget ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                          size: 18,
                          color: scheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${totalBudget > widget.budget.totalBudget ? '+' : ''}${widget.budget.currency.symbol}${formatter.format(totalBudget - widget.budget.totalBudget)} against the current cap',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              HeroCard(
                label: localizations.currentTotal,
                value: '${widget.budget.currency.symbol}${formatter.format(totalBudget)}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  TextStyle _sectionLabelStyle(BuildContext context) => TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant);

  /// Mockup's `--tint-neutral` (F1F5F3 light / 1F2723 dark) — a plain
  /// neutral surface used for the "locked" info box, distinct from the
  /// jade-tinted `secondaryContainer`. Not in [AppTheme] as a named token,
  /// so it's reproduced here directly, brightness-aware.
  Color _tintNeutral(BuildContext context) => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF1F2723)
      : const Color(0xFFF1F5F3);

  Widget _lockedField(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
      ],
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
                    '${widget.budget.currency.symbol}${formatter.format(catBudget.allocatedAmount)}',
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

/// Bottom sheet for adding or editing a single category cap.
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
