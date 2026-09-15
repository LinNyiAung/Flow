import 'package:flutter/material.dart';
import 'package:frontend/models/recurring_transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/recurrence_settings.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // Import for date formatting
import '../../models/transaction.dart';
import '../../services/api_service.dart';
import '../../providers/transaction_provider.dart';

// Extension for safely finding an element in a list (useful for dropdowns)
extension FirstWhereOrNullExtension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (E element in this) {
      if (test(element)) {
        return element;
      }
    }
    return null;
  }
}

class EditTransactionScreen extends StatefulWidget {
  final Transaction transaction; // The transaction to be edited

  EditTransactionScreen({required this.transaction});

  @override
  _EditTransactionScreenState createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  late TextEditingController _descriptionController;

  late TransactionType _selectedType;
  String? _selectedMainCategory;
  String? _selectedSubCategory;
  List<Category> _categories = []; // List to hold fetched categories
  bool _isLoadingCategories = false;
  late DateTime _selectedDate; // Will be initialized with the transaction's date

  TransactionRecurrence? _recurrence;

  late Currency _selectedCurrency;

  late String _amountText;

  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();

    // Initialize form fields with the data from the passed transaction
    _amountText = _formatAmountForField(widget.transaction.amount);
    _descriptionController = TextEditingController(text: widget.transaction.description ?? '');
    _selectedType = widget.transaction.type;
    _selectedMainCategory = widget.transaction.mainCategory;
    _selectedSubCategory = widget.transaction.subCategory;
    _selectedDate = widget.transaction.date; // Initialize with the transaction's date
    _recurrence = widget.transaction.recurrence;
    _selectedCurrency = widget.transaction.currency;

    _loadCategories(); // Load categories specific to the transaction's type
  }

  // Load categories from the API based on the selected transaction type
  Future<void> _loadCategories() async {
    setState(() {
      _isLoadingCategories = true; // Show loading indicator
    });

    try {
      final categories = await ApiService.getCategories(_selectedType);

      // Validate and re-select categories if they exist in the new list
      String? validatedMainCategory;
      String? validatedSubCategory;

      if (_selectedMainCategory != null && categories.isNotEmpty) {
        final matchingCategory = categories.firstWhereOrNull(
          (cat) => cat.mainCategory == _selectedMainCategory,
        );

        if (matchingCategory != null) {
          validatedMainCategory = matchingCategory.mainCategory; // Keep the valid main category
          if (_selectedSubCategory != null) {
            // Check if the previously selected sub-category is still valid
            if (matchingCategory.subCategories.contains(_selectedSubCategory)) {
              validatedSubCategory = _selectedSubCategory; // Keep the valid sub-category
            }
          }
        }
      }

      setState(() {
        _categories = categories;
        _selectedMainCategory = validatedMainCategory; // Update with validated category
        _selectedSubCategory = validatedSubCategory; // Update with validated sub-category
        _isLoadingCategories = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingCategories = false;
        print("Error loading categories: $e"); // Log error for debugging
      });
    }
  }

  // Function to show the date picker dialog
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate, // Pre-fill with the current selected date
      firstDate: DateTime(2000), // Set the earliest possible date
      lastDate: DateTime.now().add(Duration(days: 365)), // Allow future dates for a year
      builder: (BuildContext context, Widget? child) {
        return child!;
      },
    );
    // If a date was picked and it's different from the current selection, update the state
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _pressKey(String key) {
    setState(() {
      if (key == '⌫') {
        if (_amountText.isNotEmpty) {
          _amountText = _amountText.substring(0, _amountText.length - 1);
        }
      } else if (key == '.') {
        if (!_amountText.contains('.')) {
          _amountText = _amountText.isEmpty ? '0.' : '$_amountText.';
        }
      } else {
        if (_amountText.contains('.')) {
          final decimals = _amountText.split('.')[1];
          if (decimals.length >= 2) return;
        }
        if (_amountText.replaceAll('.', '').length >= 12) return;
        if (_amountText == '0') {
          _amountText = key;
        } else {
          _amountText += key;
        }
      }
    });
  }

  String get _displayAmount {
    if (_amountText.isEmpty) return '0';
    final dotIndex = _amountText.indexOf('.');
    if (dotIndex == -1) {
      final n = int.tryParse(_amountText) ?? 0;
      return NumberFormat('#,##0').format(n);
    }
    final intPart = _amountText.substring(0, dotIndex);
    final fracPart = _amountText.substring(dotIndex + 1);
    final n = int.tryParse(intPart.isEmpty ? '0' : intPart) ?? 0;
    return '${NumberFormat('#,##0').format(n)}.$fracPart';
  }

  double? _parsedAmount() {
    var text = _amountText;
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return double.tryParse(text);
  }

  String _formatAmountForField(double amount) {
    if (amount == amount.roundToDouble()) {
      return amount.toInt().toString();
    }
    var s = amount.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  String _dateRowLabel() {
    return DateFormat('d MMM yyyy').format(_selectedDate);
  }

  Future<void> _editNote() async {
    final localizations = AppLocalizations.of(context);
    final controller = TextEditingController(text: _descriptionController.text);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.descriptionLabel),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: InputDecoration(hintText: localizations.descriptionHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(localizations.dialogCancel)),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: Text(localizations.save)),
        ],
      ),
    );
    if (result != null) {
      setState(() {
        _descriptionController.text = result.trim();
      });
    }
  }

  void _openCategorySheet({String? initialMain}) {
    final localizations = AppLocalizations.of(context);
    String? viewingMain = initialMain;
    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final scheme = Theme.of(context).colorScheme;
            final currentMainData =
                viewingMain == null ? null : _categories.firstWhereOrNull((c) => c.mainCategory == viewingMain);
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (viewingMain == null) ...[
                    Text(localizations.pickCategoryTitle, style: Theme.of(context).textTheme.titleLarge),
                    SizedBox(height: 4),
                    Text(
                      localizations.thenChooseSubCategoryHint,
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        InkWell(
                          onTap: () => setSheetState(() => viewingMain = null),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(color: AppTheme.trackFor(context), shape: BoxShape.circle),
                            child: Icon(Icons.arrow_back_rounded, size: 20),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                viewingMain!,
                                style: Theme.of(context).textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                localizations.chooseSubCategoryTitle,
                                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: 14),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: viewingMain == null
                          ? (_categories.isEmpty
                              ? Center(
                                  child: _isLoadingCategories
                                      ? CircularProgressIndicator()
                                      : Text(localizations.noCategoriesLabel, style: TextStyle(color: scheme.onSurfaceVariant)),
                                )
                              : ListView.separated(
                                  itemCount: _categories.length,
                                  separatorBuilder: (_, __) => Divider(height: 1, indent: 66),
                                  itemBuilder: (context, index) {
                                    final cat = _categories[index];
                                    return ListTile(
                                      leading: Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: scheme.secondaryContainer,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.category_rounded, size: 20, color: scheme.primary),
                                      ),
                                      title: Text(
                                        cat.mainCategory,
                                        style: TextStyle(fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        '${cat.subCategories.length} ${localizations.subCategoriesCountLabel}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
                                      onTap: () => setSheetState(() => viewingMain = cat.mainCategory),
                                    );
                                  },
                                ))
                          : ListView.separated(
                              itemCount: currentMainData?.subCategories.length ?? 0,
                              separatorBuilder: (_, __) => Divider(height: 1, indent: 16),
                              itemBuilder: (context, index) {
                                final sub = currentMainData!.subCategories[index];
                                final isSelected = viewingMain == _selectedMainCategory && sub == _selectedSubCategory;
                                return ListTile(
                                  title: Text(
                                    sub,
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: isSelected ? Icon(Icons.check_circle_rounded, color: scheme.primary) : null,
                                  onTap: () {
                                    setState(() {
                                      _selectedMainCategory = viewingMain;
                                      _selectedSubCategory = sub;
                                    });
                                    Navigator.pop(sheetContext);
                                  },
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openRepeatSheet() {
    final localizations = AppLocalizations.of(context);
    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(localizations.repeatLabel, style: Theme.of(context).textTheme.titleLarge),
              SizedBox(height: 12),
              RecurrenceSettings(
                initialRecurrence: _recurrence,
                transactionDate: _selectedDate,
                startEnabled: true,
                onRecurrenceChanged: (recurrence) {
                  setState(() {
                    _recurrence = recurrence;
                  });
                },
              ),
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: () => Navigator.pop(sheetContext), child: Text(localizations.doneLabel)),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactionProvider = Provider.of<TransactionProvider>(context);
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isInflow = _selectedType == TransactionType.inflow;
    final typeInk = isInflow ? scheme.primary : scheme.error;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
        title: Text(localizations.editTransactionTitle, style: TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
            onPressed: _showDeleteSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Type segmented control
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: AppTheme.trackFor(context), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(child: _typeSegment(localizations.outflow, TransactionType.outflow)),
                    Expanded(child: _typeSegment(localizations.inflow, TransactionType.inflow)),
                  ],
                ),
              ),

              // Amount display
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 20, 0, 6),
                child: Column(
                  children: [
                    Text(
                      '${localizations.amountLabel} · ${_selectedCurrency.name.toUpperCase()}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _selectedCurrency.symbol,
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                        ),
                        SizedBox(width: 4),
                        Text(_displayAmount, style: AppTheme.money(40, weight: FontWeight.w800, color: typeInk)),
                      ],
                    ),
                  ],
                ),
              ),

              SizedBox(height: 14),

              // Category / date / note / convert-currency card
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: const Color(0x14101815), blurRadius: 3, offset: Offset(0, 1))],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    InkWell(
                      onTap: () => _openCategorySheet(),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(Icons.category_rounded, color: scheme.onSurface),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedSubCategory ??
                                        (_selectedMainCategory != null
                                            ? localizations.selectSubCategoryHint
                                            : localizations.chooseCategoryFallback),
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    _selectedMainCategory ?? localizations.categoryAndSubCategoryFallback,
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 1, indent: 52),
                    InkWell(
                      onTap: () => _selectDate(context),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(Icons.event_rounded, color: scheme.onSurface),
                            SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                _dateRowLabel(),
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(Icons.expand_more_rounded, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 1, indent: 52),
                    InkWell(
                      onTap: _editNote,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(Icons.notes_rounded, color: scheme.onSurface),
                            SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                _descriptionController.text.isEmpty
                                    ? localizations.descriptionHint
                                    : _descriptionController.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: _descriptionController.text.isEmpty ? scheme.onSurfaceVariant : scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 1, indent: 52),
                    InkWell(
                      onTap: () {
                        if (_amountText.isEmpty) {
                          _showError(localizations.enterAmountBeforeConverting);
                          return;
                        }
                        _showCurrencyConversionDialog();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(Icons.currency_exchange_rounded, color: scheme.onSurface),
                            SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                localizations.convertCurrency,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Repeat row — only for transactions that are not themselves auto-created
              if (widget.transaction.parentTransactionId == null) ...[
                SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: const Color(0x14101815), blurRadius: 3, offset: Offset(0, 1))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _openRepeatSheet,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.autorenew_rounded, color: scheme.onSurface),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(localizations.repeatLabel, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                SizedBox(height: 2),
                                Text(
                                  _recurrence?.enabled == true ? _recurrence!.config!.getDisplayText() : localizations.offLabel,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _recurrence?.enabled ?? false,
                            onChanged: (value) {
                              if (value) {
                                _openRepeatSheet();
                              } else {
                                setState(() => _recurrence = null);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // Auto-created schedule card
              if (widget.transaction.parentTransactionId != null)
                FutureBuilder<Transaction?>(
                  future: ApiService.getTransaction(widget.transaction.parentTransactionId!),
                  builder: (context, snapshot) {
                    final parentRecurrenceEnabled = snapshot.hasData && snapshot.data?.recurrence?.enabled == true;

                    return Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.autorenew_rounded, color: scheme.tertiary),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    localizations.autoCreatedTransactionTitle,
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onTertiaryContainer),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 6),
                            Text(
                              parentRecurrenceEnabled
                                  ? localizations.autoCreatedDescriptionRecurring
                                  : localizations.autoCreatedDescriptionDisabled,
                              style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer, height: 1.4),
                            ),
                            SizedBox(height: 14),
                            if (parentRecurrenceEnabled)
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _showDisableRecurrenceDialog,
                                  style: FilledButton.styleFrom(backgroundColor: scheme.tertiary),
                                  icon: Icon(Icons.stop_circle_rounded),
                                  label: Text(localizations.stopFutureAutoCreation),
                                ),
                              ),
                            SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _viewParentTransaction,
                                icon: Icon(Icons.repeat_rounded),
                                label: Text(localizations.viewParentTransaction),
                              ),
                            ),
                            if (!parentRecurrenceEnabled && snapshot.hasData)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: AppTheme.trackFor(context), borderRadius: BorderRadius.circular(8)),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline_rounded, color: scheme.onSurfaceVariant, size: 16),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          localizations.recurringScheduleStopped,
                                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.3),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

              if (widget.transaction.parentTransactionId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppTheme.trackFor(context), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: scheme.onSurfaceVariant),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            localizations.recurringSettingsStopDes,
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (transactionProvider.error != null)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: scheme.error),
                      SizedBox(width: 8),
                      Expanded(child: Text(transactionProvider.error!, style: TextStyle(color: scheme.onErrorContainer))),
                    ],
                  ),
                ),

              SizedBox(height: 18),

              // Keypad
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', '⌫'].map((k) {
                  return _keypadKey(k);
                }).toList(),
              ),

              SizedBox(height: 20),
              FilledButton(
                onPressed: transactionProvider.isLoading ? null : _updateTransaction,
                child: transactionProvider.isLoading
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(localizations.updateTransactionButton),
              ),
              SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(localizations.dialogCancel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeSegment(String label, TransactionType type) {
    final selected = _selectedType == type;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        if (_selectedType != type) {
          setState(() {
            _selectedType = type;
            _selectedMainCategory = null;
            _selectedSubCategory = null;
          });
          _loadCategories();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).cardTheme.color : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected ? [BoxShadow(color: const Color(0x14101815), blurRadius: 2)] : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _keypadKey(String label) {
    final width = (MediaQuery.of(context).size.width - 32 - 16) / 3;
    return InkWell(
      onTap: () => _pressKey(label),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: const Color(0x14101815), blurRadius: 2)],
        ),
        child: label == '⌫'
            ? Icon(Icons.backspace_rounded, size: 20)
            : Text(label, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _showDisableRecurrenceDialog() {
    final localizations = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.stop_circle_rounded, color: scheme.tertiary),
              SizedBox(width: 12),
              Expanded(child: Text(localizations.stopRecurringDialogTitle, style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(localizations.stopRecurringDialogContent),
              SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: scheme.tertiary, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        localizations.stopRecurringDialogInfo,
                        style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.dialogCancel)),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _disableParentRecurrence();
              },
              style: FilledButton.styleFrom(backgroundColor: scheme.tertiary),
              icon: Icon(Icons.stop_rounded),
              label: Text(localizations.stopRecurringButton),
            ),
          ],
        );
      },
    );
  }

  void _showCurrencyConversionDialog() {
    final localizations = AppLocalizations.of(context);
    final TextEditingController rateController = TextEditingController();
    Currency? targetCurrency;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final scheme = Theme.of(context).colorScheme;
            return AlertDialog(
              title: Text(localizations.convertCurrency),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppTheme.trackFor(context), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          Text(localizations.current, style: TextStyle(color: scheme.onSurfaceVariant)),
                          Expanded(
                            child: Text(
                              '${_selectedCurrency.symbol} ${_selectedCurrency.displayName}',
                              textAlign: TextAlign.end,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(localizations.convertTo, style: TextStyle(fontWeight: FontWeight.w600)),
                    SizedBox(height: 8),
                    DropdownButtonFormField<Currency>(
                      isExpanded: true,
                      hint: Text(localizations.selectTargetCurrency),
                      value: targetCurrency,
                      items: Currency.values.where((c) => c != _selectedCurrency).map((currency) {
                        return DropdownMenuItem(value: currency, child: Text('${currency.symbol} - ${currency.displayName}'));
                      }).toList(),
                      onChanged: (value) => setDialogState(() => targetCurrency = value),
                    ),
                    SizedBox(height: 16),
                    Text(localizations.exchangeRate, style: TextStyle(fontWeight: FontWeight.w600)),
                    SizedBox(height: 8),
                    TextField(
                      controller: rateController,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        hintText: localizations.egExchangeRateHint,
                        prefixText: '1 ${_selectedCurrency.symbol} = ',
                        suffixText: targetCurrency?.symbol ?? '',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    SizedBox(height: 12),
                    if (targetCurrency != null && rateController.text.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(localizations.preview, style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.jadeLabelFor(context))),
                            SizedBox(height: 4),
                            Text(
                              '${_selectedCurrency.symbol}${(_parsedAmount() ?? 0).toStringAsFixed(2)} → ${targetCurrency!.symbol}${((_parsedAmount() ?? 0) * (double.tryParse(rateController.text) ?? 1)).toStringAsFixed(2)}',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(localizations.dialogCancel)),
                FilledButton(
                  onPressed: () async {
                    if (targetCurrency == null || rateController.text.isEmpty) {
                      _showError(localizations.pleaseFillAllFields);
                      return;
                    }
                    final rate = double.tryParse(rateController.text);
                    if (rate == null || rate <= 0) {
                      _showError(localizations.pleaseEnterValidExchangeRate);
                      return;
                    }
                    Navigator.pop(dialogContext);
                    _convertCurrency(targetCurrency!, rate);
                  },
                  child: Text(localizations.convert),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _convertCurrency(Currency targetCurrency, double exchangeRate) {
    final currentAmount = _parsedAmount();
    final localizations = AppLocalizations.of(context);
    if (currentAmount == null) {
      _showError(localizations.pleaseEnterValidAmount);
      return;
    }

    final convertedAmount = currentAmount * exchangeRate;

    // ONLY UPDATE LOCAL STATE - don't save to backend
    setState(() {
      _selectedCurrency = targetCurrency;
      _amountText = _formatAmountForField(convertedAmount);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${localizations.currencyConvertedMessage} ${targetCurrency.symbol}${convertedAmount.toStringAsFixed(2)}')),
    );
  }

  void _disableParentRecurrence() async {
    final localizations = AppLocalizations.of(context);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
      );

      await ApiService.disableParentTransactionRecurrence(widget.transaction.id);

      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.successAutoCreationStopped)),
        );
      }

      if (mounted) {
        final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
        transactionProvider.fetchTransactions();
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    }
  }

  void _viewParentTransaction() async {
    final localizations = AppLocalizations.of(context);
    if (widget.transaction.parentTransactionId == null) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
      );

      final parentTransaction = await ApiService.getTransaction(widget.transaction.parentTransactionId!);

      Navigator.pop(context);

      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EditTransactionScreen(transaction: parentTransaction)),
      );

      if (result == true || result == 'deleted') {
        Navigator.pop(context, result);
      }
    } catch (e) {
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${localizations.errorLoadParentFailed} ${e.toString().replaceAll('Exception: ', '')}')),
      );
    }
  }

  // Function to handle the update transaction logic
  void _updateTransaction() async {
    final localizations = AppLocalizations.of(context);

    if (_amountText.isEmpty) {
      _showError(localizations.validationAmountRequired);
      return;
    }
    final amount = _parsedAmount();
    if (amount == null) {
      _showError(localizations.pleaseEnterAValidAmount);
      return;
    }
    if (amount <= 0) {
      _showError(localizations.validationAmountPositive);
      return;
    }
    if (_selectedMainCategory == null) {
      _showError(localizations.validationMainCategoryRequired);
      return;
    }
    if (_selectedSubCategory == null) {
      _showError(localizations.validationSubCategoryRequired);
      return;
    }

    final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);

    TransactionRecurrence? recurrenceToSend;
    if (_recurrence != null && _recurrence!.enabled) {
      recurrenceToSend = _recurrence;
    } else {
      recurrenceToSend = TransactionRecurrence(
        enabled: false,
        config: null,
        lastCreatedDate: null,
        parentTransactionId: null,
      );
    }

    final success = await transactionProvider.updateTransaction(
      transactionId: widget.transaction.id,
      type: _selectedType,
      mainCategory: _selectedMainCategory!,
      subCategory: _selectedSubCategory!,
      date: _selectedDate,
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      amount: amount,
      currency: _selectedCurrency,
      context: context,
      recurrence: recurrenceToSend,
    );

    if (success) {
      Navigator.pop(context, true);
    }
  }

  // Function to show the delete confirmation sheet
  void _showDeleteSheet() {
    final localizations = AppLocalizations.of(context);
    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final scheme = Theme.of(context).colorScheme;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: scheme.errorContainer, shape: BoxShape.circle),
                  child: Icon(Icons.delete_rounded, color: scheme.error),
                ),
                SizedBox(height: 14),
                Text(localizations.deleteTransactionTitle, style: Theme.of(context).textTheme.titleLarge),
                SizedBox(height: 8),
                Text(localizations.deleteConfirmMessage, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.5)),
                SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: scheme.error),
                    onPressed: _isDeleting
                        ? null
                        : () async {
                            setSheetState(() => _isDeleting = true);
                            setState(() => _isDeleting = true);
                            await _deleteTransaction();
                            if (mounted) Navigator.pop(sheetContext);
                          },
                    child: _isDeleting
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(localizations.delete),
                  ),
                ),
                SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: _isDeleting ? null : () => Navigator.pop(sheetContext),
                    child: Text(localizations.keepItButton),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Function to handle the actual deletion of the transaction
  Future<void> _deleteTransaction() async {
    final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);

    final success = await transactionProvider.deleteTransaction(
      widget.transaction.id,
      context: context,
    );

    if (success) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
        Navigator.pop(context, 'deleted');
      }
    } else {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  // Dispose of controllers to prevent memory leaks
  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }
}
