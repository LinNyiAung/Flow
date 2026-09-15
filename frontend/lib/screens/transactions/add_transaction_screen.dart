import 'package:flutter/material.dart';
import 'package:frontend/models/recurring_transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/recurrence_settings.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // Import for date formatting
import '../../models/transaction.dart';
import '../../services/api_service.dart';
import '../../providers/transaction_provider.dart';
import 'voice_input_screen.dart';
import 'image_input_screen.dart';

/// Display order for currency chips — MMK first, matching the product's
/// Myanmar-first audience rather than the model's declaration order.
const _kCurrencyOrder = [Currency.mmk, Currency.usd, Currency.thb];

// Extension for safely finding an element in a list
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

class AddTransactionScreen extends StatefulWidget {
  @override
  _AddTransactionScreenState createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _descriptionController = TextEditingController();

  TransactionType _selectedType = TransactionType.outflow; // Default to outflow (expense)
  String? _selectedMainCategory;
  String? _selectedSubCategory;
  List<Category> _categories = []; // List to hold fetched categories
  bool _isLoadingCategories = false;
  DateTime _selectedDate = DateTime.now(); // Default date is today

  TransactionRecurrence? _recurrence;

  Currency _selectedCurrency = Currency.usd;

  String _amountText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      setState(() {
        _selectedCurrency = authProvider.defaultCurrency;
      });
    });

    _loadCategories(); // Load categories when the screen initializes
  }

  // Load categories from the API based on the selected transaction type
  Future<void> _loadCategories() async {
    setState(() {
      _isLoadingCategories = true; // Show loading indicator
    });

    try {
      final categories = await ApiService.getCategories(_selectedType);
      setState(() {
        _categories = categories;
        // Reset selected categories when type changes or categories load to ensure validity
        _selectedMainCategory = null;
        _selectedSubCategory = null;
        _isLoadingCategories = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingCategories = false;
        // Optionally display an error message to the user
        print("Error loading categories: $e");
      });
    }
  }

  /// One real sub-category per main category, capped at 6 — quick-pick
  /// shortcuts below the category row. No usage-frequency data exists, so
  /// this takes the first sub-category of each main category rather than
  /// fabricating a "most used" ranking.
  List<(String, String)> _quickPickSubCategories() {
    final picks = <(String, String)>[];
    for (final cat in _categories) {
      if (cat.subCategories.isNotEmpty) {
        picks.add((cat.mainCategory, cat.subCategories.first));
      }
      if (picks.length >= 6) break;
    }
    return picks;
  }

  // Function to show the date picker dialog
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate, // Pre-fill with the current selected date
      firstDate: DateTime(2000), // Set the earliest possible date
      lastDate: DateTime.now().add(Duration(days: 365)), // Set the latest possible date (1 year from now)
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

  Future<void> _goVoice() async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => VoiceInputScreen()));
    if (result == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _goScan() async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => ImageInputScreen()));
    if (result == true && mounted) Navigator.pop(context, true);
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
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day;
    final formatted = DateFormat('d MMM yyyy').format(_selectedDate);
    return isToday ? 'Today, $formatted' : formatted;
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
        leading: IconButton(icon: Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        title: Text(localizations.addTransactionTitle, style: TextStyle(fontSize: 18)),
        actions: [
          _appBarTonalIcon(icon: Icons.mic_rounded, tooltip: localizations.speakItTooltip, onTap: _goVoice),
          const SizedBox(width: 6),
          _appBarTonalIcon(icon: Icons.document_scanner_rounded, tooltip: localizations.scanReceipt, onTap: _goScan),
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 12),
            child: Center(
              child: GestureDetector(
                onTap: transactionProvider.isLoading ? null : _addTransaction,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: transactionProvider.isLoading ? scheme.outline : scheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: transactionProvider.isLoading
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                          localizations.save,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                ),
              ),
            ),
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
              SizedBox(height: 12),

              // Currency chips
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: _kCurrencyOrder.map((currency) => _currencyPill(currency)).toList(),
              ),

              // Amount display
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${localizations.amountLabel} · ${_selectedCurrency.name.toUpperCase()}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () {
                            if (_amountText.isEmpty) {
                              _showError(localizations.enterAmountBeforeConverting);
                              return;
                            }
                            _showCurrencyConversionDialog();
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Icon(Icons.currency_exchange_rounded, size: 16, color: scheme.primary),
                        ),
                      ],
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
                        Text(
                          _displayAmount,
                          style: AppTheme.money(
                            42,
                            weight: FontWeight.w800,
                            color: _amountText.isEmpty ? scheme.onSurfaceVariant : typeInk,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Category picker
              InkWell(
                onTap: () => _openCategorySheet(),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: const Color(0x14101815), blurRadius: 3, offset: Offset(0, 1))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
                        child: Icon(Icons.category_rounded, color: scheme.primary),
                      ),
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
                      Icon(Icons.unfold_more_rounded, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              if (_categories.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _quickPickSubCategories().map((pick) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: Icon(Icons.label_rounded, size: 16, color: scheme.primary),
                            label: Text(pick.$2),
                            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
                            backgroundColor: Theme.of(context).cardTheme.color,
                            side: BorderSide(color: scheme.outline),
                            onPressed: () => setState(() {
                              _selectedMainCategory = pick.$1;
                              _selectedSubCategory = pick.$2;
                            }),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

              SizedBox(height: 18),

              // Date / note / repeat card
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
                                    _recurrence?.enabled == true
                                        ? _recurrence!.config!.getDisplayText()
                                        : localizations.offLabel,
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
                  ],
                ),
              ),

              if (transactionProvider.error != null)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: scheme.error),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          transactionProvider.error!,
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                      ),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _currencyPill(Currency currency) {
    final selected = _selectedCurrency == currency;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => setState(() => _selectedCurrency = currency),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(8),
          border: selected ? null : Border.all(color: scheme.outline),
        ),
        child: Text(
          '${currency.symbol} ${currency.name.toUpperCase()}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _appBarTonalIcon({required IconData icon, required String tooltip, required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
          child: Icon(icon, size: 22, color: scheme.primary),
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                    if (targetCurrency != null && rateController.text.isNotEmpty && _amountText.isNotEmpty)
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
                  onPressed: () {
                    if (targetCurrency == null || rateController.text.isEmpty) {
                      _showError(localizations.pleaseFillAllFields);
                      return;
                    }
                    if (_amountText.isEmpty) {
                      _showError(localizations.pleaseEnterAmountFirst);
                      return;
                    }
                    final rate = double.tryParse(rateController.text);
                    if (rate == null || rate <= 0) {
                      _showError(localizations.pleaseEnterValidExchangeRate);
                      return;
                    }
                    Navigator.pop(dialogContext);
                    _applyConversion(targetCurrency!, rate);
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

  void _applyConversion(Currency targetCurrency, double exchangeRate) {
    final currentAmount = _parsedAmount();
    final localizations = AppLocalizations.of(context);
    if (currentAmount == null) {
      _showError(localizations.pleaseEnterValidAmount);
      return;
    }

    final convertedAmount = currentAmount * exchangeRate;

    setState(() {
      _selectedCurrency = targetCurrency;
      _amountText = _formatAmountForField(convertedAmount);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${localizations.currencyConvertedMessage} ${targetCurrency.symbol}${convertedAmount.toStringAsFixed(2)}')),
    );
  }

  // Function to handle adding the transaction
  void _addTransaction() async {
    final localizations = AppLocalizations.of(context);

    if (_amountText.isEmpty) {
      _showError(localizations.validationAmountRequired);
      return;
    }
    final amount = _parsedAmount();
    if (amount == null) {
      _showError(localizations.validationAmountInvalid);
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

    final success = await transactionProvider.createTransaction(
      type: _selectedType,
      mainCategory: _selectedMainCategory!,
      subCategory: _selectedSubCategory!,
      date: _selectedDate,
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      amount: amount,
      currency: _selectedCurrency,
      context: context,
      recurrence: _recurrence,
    );

    if (success) {
      Navigator.pop(context, true);
    }
  }

  // Dispose of controllers to prevent memory leaks
  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }
}
