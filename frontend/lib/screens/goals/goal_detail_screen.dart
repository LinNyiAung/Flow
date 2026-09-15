import 'package:flutter/material.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/progress_meter.dart';
import 'package:frontend/widgets/status_pill.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/goal.dart';
import '../../providers/goal_provider.dart';
import '../../providers/transaction_provider.dart';

/// Mockup's `--accent`: identical to `--primary` in light, but a distinct,
/// brighter teal in dark. See goals_screen.dart for the full rationale.
Color _accentColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark ? theme.colorScheme.secondary : theme.colorScheme.primary;
}

class GoalDetailScreen extends StatefulWidget {
  final Goal goal;

  GoalDetailScreen({required this.goal});

  @override
  _GoalDetailScreenState createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  final _contributionController = TextEditingController();
  final _formatter = NumberFormat("#,##0.00", "en_US");
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
    final scheme = Theme.of(context).colorScheme;
    if (_contributionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.validationAmountRequired),
          backgroundColor: scheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final amount = double.tryParse(_contributionController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.pleaseEnterAValidAmount),
          backgroundColor: scheme.error,
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
      if (!mounted) return;
      Navigator.pop(context); // Close sheet
      await _refreshGoalData(); // Refresh the goal data
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isAdd ? localizations.fundsAddedSuccessfully : localizations.fundsWithdrawnSuccessfully),
          backgroundColor: scheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      if (!mounted) return;
      Navigator.pop(context); // Close sheet
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(goalProvider.error ?? localizations.operationFailed),
          backgroundColor: scheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showManageFundsSheet() {
    final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);

    // Fetch balance for the goal's currency
    transactionProvider.fetchBalance(currency: _currentGoal.currency);

    final localizations = AppLocalizations.of(context);
    final canAdd = _currentGoal.status == GoalStatus.active;
    final canWithdraw = _currentGoal.currentAmount > 0;

    _isContributionLoading = false;
    _contributionController.clear();
    bool isAddMode = canAdd;

    showAppBottomSheet(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final scheme = Theme.of(sheetContext).colorScheme;
          final balanceProvider = Provider.of<TransactionProvider>(sheetContext);
          final availableBalance = balanceProvider.balance != null && balanceProvider.balance!.currency == _currentGoal.currency
              ? balanceProvider.balance!.availableBalance
              : 0.0;

          Future<void> submit() async {
            setSheetState(() => _isContributionLoading = true);
            await _contributeToGoal(isAddMode);
            if (mounted) setSheetState(() => _isContributionLoading = false);
          }

          // Mockup's segmented control tracks/thumbs use `--seg-track` /
          // `--seg-thumb`, which are NOT the generic `--track`/card tokens —
          // in dark mode `--seg-track` equals `--surface` (not `--track`)
          // and `--seg-thumb` equals `--divider` (not `--surface`). Using
          // the generic tokens here made the track glow light-grey and the
          // selected thumb disappear against it in dark mode.
          final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
          final segTrackColor = isDark ? scheme.surface : AppTheme.trackFor(sheetContext);
          final segThumbColor = isDark ? scheme.outlineVariant : Colors.white;

          // Quick-amount presets, mirroring the mockup's `fundQuick` chips.
          // The base amount is mode-aware: Add is capped by what's
          // available to move, Withdraw by what the goal currently holds.
          final quickBase = isAddMode ? availableBalance : _currentGoal.currentAmount;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(localizations.manageFunds, style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '${localizations.available}: ${_currentGoal.currency.symbol}${_formatter.format(availableBalance)}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
              ),
              if (canAdd && canWithdraw) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: segTrackColor, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _isContributionLoading ? null : () => setSheetState(() => isAddMode = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isAddMode ? segThumbColor : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              localizations.add,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isAddMode ? scheme.primary : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: _isContributionLoading ? null : () => setSheetState(() => isAddMode = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !isAddMode ? segThumbColor : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              localizations.withdraw,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: !isAddMode ? scheme.error : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // Mockup shows the amount as a single giant centered number
              // (`{{ fundAmountStr }}`, 36/800) rather than a conventional
              // labeled field — this keeps the real TextField (so typing,
              // validation and parsing are untouched) but styles it to
              // match that look.
              TextField(
                controller: _contributionController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                enabled: !_isContributionLoading,
                autofocus: true,
                textAlign: TextAlign.center,
                style: AppTheme.money(36, weight: FontWeight.w800, color: scheme.onSurface),
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  hintText: '0',
                  hintStyle: AppTheme.money(36, weight: FontWeight.w800, color: AppTheme.hintFor(context)),
                  prefixText: '${_currentGoal.currency.symbol} ',
                  prefixStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [0.25, 0.5, 1.0].map((frac) {
                  final amount = quickBase * frac;
                  final label = frac == 1.0 ? '100%' : '${(frac * 100).round()}%';
                  final enabled = !_isContributionLoading && quickBase > 0;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: frac == 1.0 ? 0 : 8),
                      child: OutlinedButton(
                        onPressed: enabled
                            ? () => setSheetState(() => _contributionController.text = amount.toStringAsFixed(2))
                            : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.onSurface,
                          side: BorderSide(color: scheme.outline),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isContributionLoading ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAddMode ? scheme.primary : scheme.error,
                  ),
                  child: _isContributionLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(isAddMode ? localizations.add : localizations.withdraw),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _isContributionLoading ? null : () => Navigator.pop(sheetContext),
                  child: Text(localizations.dialogCancel),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditDialog() {
    final nameController = TextEditingController(text: _currentGoal.name);
    final targetAmountController = TextEditingController(text: _currentGoal.targetAmount.toString());
    DateTime? targetDate = _currentGoal.targetDate;
    GoalType selectedGoalType = _currentGoal.goalType;
    final localizations = AppLocalizations.of(context);

    // Matches the app's bottom-sheet convention used everywhere else on this
    // screen (Manage Funds, delete confirmation) rather than a centered
    // AlertDialog, which was the one editing flow still using the old style.
    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setDialogState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(localizations.editGoal, style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: localizations.goalName,
                    prefixIcon: const Icon(Icons.label_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<GoalType>(
                  value: selectedGoalType,
                  decoration: InputDecoration(
                    labelText: localizations.goalType,
                    prefixIcon: const Icon(Icons.category_rounded),
                  ),
                  isExpanded: true,
                  items: GoalType.values.map((type) {
                    IconData icon;
                    switch (type) {
                      case GoalType.savings:
                        icon = Icons.savings_rounded;
                        break;
                      case GoalType.debt_reduction:
                        icon = Icons.money_off_rounded;
                        break;
                      case GoalType.large_purchase:
                        icon = Icons.shopping_bag_rounded;
                        break;
                    }
                    return DropdownMenuItem(
                      value: type,
                      child: Row(
                        children: [
                          Icon(icon, size: 20),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              type.name.replaceAll('_', ' ').toUpperCase(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedGoalType = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: targetAmountController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: localizations.targetAmount,
                    prefixIcon: const Icon(Icons.attach_money_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: targetDate ?? DateTime.now().add(Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(Duration(days: 3650)),
                      // The picker already inherits the app's theme (jade in
                      // light, darkPrimary in dark) — no override needed.
                      // The previous override hardcoded AppTheme.jade,
                      // which forced the light-mode green even in dark mode.
                    );
                    if (picked != null) {
                      setDialogState(() {
                        targetDate = picked;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            targetDate == null ? localizations.selectTargetDate : DateFormat('MMM dd, yyyy').format(targetDate!),
                            style: TextStyle(
                              fontSize: 14,
                              color: targetDate == null ? AppTheme.hintFor(context) : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(localizations.enterAGoalName),
                            backgroundColor: Theme.of(context).colorScheme.error,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }

                      final targetAmount = double.tryParse(targetAmountController.text);
                      if (targetAmount == null || targetAmount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(localizations.pleaseEnterAValidAmount),
                            backgroundColor: Theme.of(context).colorScheme.error,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }

                      Navigator.pop(sheetContext); // Close sheet
                      setState(() {
                        _isLoading = true;
                      });

                      final goalProvider = Provider.of<GoalProvider>(context, listen: false);
                      final success = await goalProvider.updateGoal(
                        goalId: _currentGoal.id,
                        name: nameController.text.trim(),
                        targetAmount: targetAmount,
                        targetDate: targetDate,
                        goalType: selectedGoalType,
                      );

                      setState(() {
                        _isLoading = false;
                      });

                      if (!mounted) return;
                      if (success) {
                        await _refreshGoalData();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(localizations.goalUpdatedSuccessfully),
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(goalProvider.error ?? localizations.failedToUpdateGoal),
                            backgroundColor: Theme.of(context).colorScheme.error,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    child: Text(localizations.save),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: Text(localizations.dialogCancel),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  void _showDeleteDialog() {
    final localizations = AppLocalizations.of(context);
    bool isDeleteLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissal while deleting
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(localizations.deleteGoal),
          content: Text(localizations.deleteGoalConfirmation),
          actions: [
            TextButton(
              onPressed: isDeleteLoading ? null : () => Navigator.pop(context),
              child: Text(localizations.dialogCancel),
            ),
            ElevatedButton(
              onPressed: isDeleteLoading
                  ? null
                  : () async {
                      setDialogState(() {
                        isDeleteLoading = true;
                      });
                      _deleteGoal();
                      // Don't reset loading state here as we're navigating away
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              child: isDeleteLoading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(localizations.delete),
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
      if (!mounted) return;
      Navigator.pop(context); // Close dialog
      Navigator.pop(context, 'deleted'); // Go back to goals screen
    } else {
      if (!mounted) return;
      Navigator.pop(context); // Close dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(goalProvider.error ?? localizations.failedToDeleteGoal),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    IconData goalIcon;
    switch (_currentGoal.goalType) {
      case GoalType.savings:
        goalIcon = Icons.savings_rounded;
        break;
      case GoalType.debt_reduction:
        goalIcon = Icons.money_off_rounded;
        break;
      case GoalType.large_purchase:
        goalIcon = Icons.shopping_bag_rounded;
        break;
    }

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.goalDetails),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context, true),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_rounded, color: scheme.onSurfaceVariant),
            onPressed: _showEditDialog,
          ),
          IconButton(icon: Icon(Icons.delete_rounded, color: scheme.error), onPressed: _showDeleteDialog),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(goalIcon),
            const SizedBox(height: 20),
            _buildDetailsCard(),
            const SizedBox(height: 16),
            _buildHeldFundsBanner(),
            const SizedBox(height: 20),

            // Action Button
            if (_currentGoal.status == GoalStatus.active || _currentGoal.currentAmount > 0)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _showManageFundsSheet, // NEW: Disable while loading
                  icon: const Icon(Icons.account_balance_wallet_rounded),
                  label: Text(localizations.manageFunds),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(IconData goalIcon) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);
    final achieved = _currentGoal.status == GoalStatus.achieved;
    final accent = _accentColor(context);
    final onHeroMuted = AppTheme.jadeLabelFor(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                child: Icon(goalIcon, color: accent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentGoal.name,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _currentGoal.targetDate != null
                          ? '${_currentGoal.goalType.name.replaceAll('_', ' ').toUpperCase()} · ${localizations.dueDatePrefix} ${DateFormat('MMM dd, yyyy').format(_currentGoal.targetDate!)}'
                          : _currentGoal.goalType.name.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onHeroMuted),
                    ),
                  ],
                ),
              ),
              if (achieved)
                StatusPill(label: localizations.achieved.toUpperCase(), background: scheme.primary, foreground: Colors.white),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  _currentGoal.displayCurrentAmount,
                  style: AppTheme.money(32, weight: FontWeight.w800, color: scheme.onPrimaryContainer),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'of ${_currentGoal.displayTargetAmount}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: onHeroMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ProgressMeter(value: _currentGoal.progressPercentage / 100, height: 8, onHero: true, overrideColor: accent),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_currentGoal.progressPercentage.toStringAsFixed(1)}% ${localizations.completed}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: onHeroMuted),
              ),
              Text(
                '${_currentGoal.displayRemainingAmount} to go',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: onHeroMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    // Order and rows match the mockup's info card exactly (target, saved,
    // remaining, currency, created). The target date is deliberately left
    // out here — it's already shown in the header subtitle above, and
    // repeating it made the card redundant with the mockup's leaner list.
    // Achieved date is appended as a genuinely new fact for achieved goals.
    final rows = <Widget>[
      _infoRow(localizations.targetAmount, _currentGoal.displayTargetAmount),
      _infoRow(localizations.currentAmount, _currentGoal.displayCurrentAmount),
      _infoRow(localizations.remaining, _currentGoal.displayRemainingAmount),
      _infoRow(localizations.currency, _currentGoal.currency.displayName, muted: true),
      _infoRow(localizations.created, DateFormat('MMMM dd, yyyy').format(_currentGoal.createdAt), muted: true),
      if (_currentGoal.achievedAt != null)
        _infoRow(localizations.achieved, DateFormat('MMMM dd, yyyy').format(_currentGoal.achievedAt!), muted: true),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localizations.goalInformation, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (var i = 0; i < rows.length; i++) ...[
              rows[i],
              if (i != rows.length - 1) ...[
                const SizedBox(height: 12),
                Container(height: 1, color: scheme.outlineVariant),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // Mockup labels are full-strength ink at weight 600 (not muted, unlike
  // most "label" text elsewhere) and values are weight 700 — only the
  // Currency/Created (and Achieved) rows use the muted ink-3 tone for
  // their value, per the prototype's info card.
  Widget _infoRow(String label, String value, {bool muted = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: muted ? scheme.onSurfaceVariant : scheme.onSurface,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildHeldFundsBanner() {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizations.moneyHeldNotSpendable,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onTertiaryContainer),
          ),
          const SizedBox(height: 4),
          Text(
            localizations.heldFundsExplanation,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onTertiaryContainer, height: 1.4),
          ),
        ],
      ),
    );
  }
}
