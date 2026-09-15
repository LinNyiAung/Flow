import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
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
  final _formatter = NumberFormat("#,##0.00", "en_US");

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
      // The picker already inherits the app's theme (jade in light,
      // darkPrimary in dark) — no override needed. The previous override
      // hardcoded AppTheme.jade, forcing light-mode green in dark mode too.
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
    final localizations = AppLocalizations.of(context);

    final success = await goalProvider.createGoal(
      name: _nameController.text.trim(),
      targetAmount: double.parse(_targetAmountController.text),
      targetDate: _targetDate,
      goalType: _selectedGoalType,
      initialContribution: _initialContributionController.text.isNotEmpty
          ? double.parse(_initialContributionController.text)
          : 0.0,
      currency: _selectedCurrency, // ADD THIS LINE
    );

    setState(() {
      _isLoading = false;
    });

    if (success) {
      await transactionProvider.fetchBalance(currency: _selectedCurrency); // Refresh balance
      if (!mounted) return;
      Navigator.pop(context, true);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(goalProvider.error ?? localizations.failedToCreateGoal),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactionProvider = Provider.of<TransactionProvider>(context);
    final availableBalance = transactionProvider.balance != null && transactionProvider.balance!.currency == _selectedCurrency
        ? transactionProvider.balance!.availableBalance
        : 0.0;
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    // Available-for-goals header recalculates live as the initial amount changes.
    final enteredInitial = double.tryParse(_initialContributionController.text) ?? 0.0;
    final remainingAfterInitial = availableBalance - enteredInitial;

    final onHeroMuted = AppTheme.jadeLabelFor(context);
    final accent = _accentColor(context);

    return Scaffold(
      appBar: AppBar(
        // Mockup uses a close (X) glyph here, not a back arrow — this is a
        // modal creation flow, dismissed rather than navigated back from.
        title: Text(localizations.createNewGoal),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: TextButton(
                onPressed: _isLoading ? null : _createGoal,
                style: TextButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: scheme.primary.withValues(alpha: 0.6),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(localizations.createGoal, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mockup's Add Goal hero is smaller than the Dashboard/Budgets
              // /Goal detail hero — `--p-container` at radius 16 (not 24)
              // with a 26px amount (not 40px) — so it's hand-built here
              // rather than reusing the shared (larger) HeroCard widget.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.availableForGoals,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: onHeroMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_selectedCurrency.symbol}${_formatter.format(availableBalance)}',
                      style: AppTheme.money(26, weight: FontWeight.w800, color: scheme.onPrimaryContainer),
                    ),
                    if (enteredInitial > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${_selectedCurrency.symbol}${_formatter.format(remainingAfterInitial)} left after this goal',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onHeroMuted),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              _sectionLabel(localizations.goalName),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: localizations.egEmergencyFund,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return localizations.pleaseEnterAGoalName;
                  }
                  return null;
                },
              ),

              const SizedBox(height: 18),

              _sectionLabel(localizations.currency),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: Currency.values.map((currency) {
                  final selected = _selectedCurrency == currency;
                  return ChoiceChip(
                    label: Text('${currency.symbol} ${currency.name.toUpperCase()}'),
                    selected: selected,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : scheme.onSurface,
                    ),
                    selectedColor: scheme.primary,
                    backgroundColor: scheme.surface,
                    side: BorderSide(color: selected ? scheme.primary : scheme.outline),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    onSelected: (_) async {
                      setState(() => _selectedCurrency = currency);
                      final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
                      await transactionProvider.fetchBalance(currency: currency);
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 18),

              _sectionLabel(localizations.goalType),
              const SizedBox(height: 8),
              Column(
                children: [
                  _goalTypeOption(
                    type: GoalType.savings,
                    icon: Icons.savings_rounded,
                    title: 'Savings',
                    subtitle: 'Put money aside for later',
                  ),
                  const SizedBox(height: 8),
                  _goalTypeOption(
                    type: GoalType.debt_reduction,
                    icon: Icons.money_off_rounded,
                    title: 'Debt reduction',
                    subtitle: 'Clear something you owe',
                  ),
                  const SizedBox(height: 8),
                  _goalTypeOption(
                    type: GoalType.large_purchase,
                    icon: Icons.shopping_bag_rounded,
                    title: 'Large purchase',
                    subtitle: 'Save towards one thing',
                  ),
                ],
              ),

              const SizedBox(height: 18),

              _sectionLabel(localizations.targetAmount),
              const SizedBox(height: 8),
              TextFormField(
                controller: _targetAmountController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: '0.00',
                  prefixIcon: Icon(Icons.flag_rounded, color: accent),
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

              const SizedBox(height: 18),

              _sectionLabel(localizations.initialContribution),
              const SizedBox(height: 8),
              TextFormField(
                controller: _initialContributionController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: '0.00',
                  prefixIcon: Icon(Icons.account_balance_wallet_rounded, color: accent),
                ),
                onChanged: (_) => setState(() {}),
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

              const SizedBox(height: 18),

              // Mockup renders Target date as a single self-contained card
              // (title + current value + chevron, radius 16, shadow — no
              // border) rather than the external-label-then-field pattern
              // used above; unlike those fields it carries its own title,
              // so no separate _sectionLabel precedes it.
              Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _selectTargetDate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                    child: Row(
                      children: [
                        Icon(Icons.event_rounded, size: 22, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                localizations.targetDate,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _targetDate == null ? localizations.selectTargetDate : DateFormat('MMM dd, yyyy').format(_targetDate!),
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.expand_more_rounded, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _goalTypeOption({
    required GoalType type,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedGoalType == type;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _selectedGoalType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? scheme.secondaryContainer : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? scheme.primary : scheme.outline),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: _accentColor(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle_rounded, color: scheme.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
