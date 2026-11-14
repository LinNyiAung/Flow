import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/date_format.dart';
import 'package:frontend/utils/date_picker_bounds.dart';
import 'package:frontend/utils/family_entries.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:provider/provider.dart';

/// Display order of the currency chips, as on New entry.
const _kCurrencyOrder = [Currency.mmk, Currency.usd, Currency.thb];

/// The transfer Home's add sheet offers: "Move to family wallet" in Personal
/// mode, "Take from family wallet" in Family mode; none outside a family or
/// while the family is read-only (the server would refuse either way).
TransferDirection? transferActionFor({required bool inFamily, required bool readOnly, required BookMode mode}) {
  if (!inFamily || readOnly) return null;
  return mode == BookMode.family ? TransferDirection.toPersonal : TransferDirection.toFamily;
}

/// Moves money between the signed-in person's wallet and their family's
/// ([direction]). True once the money moved (the caller refreshes its book
/// and says so); null when dismissed.
Future<bool?> showTransferSheet(BuildContext context, {required TransferDirection direction}) =>
    showAppBottomSheet<bool>(context: context, builder: (_) => TransferSheet(direction: direction));

/// The body of [showTransferSheet]: amount, currency (the default one
/// first), date (today) and an optional note. A refusal shows in the sheet.
class TransferSheet extends StatefulWidget {
  const TransferSheet({super.key, required this.direction});

  static const Key amountKey = ValueKey('transfer-amount');
  static const Key noteKey = ValueKey('transfer-note');
  static const Key dateKey = ValueKey('transfer-date');
  static const Key submitKey = ValueKey('transfer-submit');
  static Key currencyKey(Currency currency) => ValueKey('transfer-currency-${currency.name}');

  final TransferDirection direction;

  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late Currency _currency;
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currency = Provider.of<AuthProvider>(context, listen: false).defaultCurrency;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _parsedAmount {
    final value = double.tryParse(_amount.text);
    return value == null || value <= 0 ? null : value;
  }

  void _setCurrency(Currency currency) {
    setState(() {
      _currency = currency;
      _error = null;
      // Kyat is whole: drop any decimals typed for another currency.
      if (currency == Currency.mmk && _amount.text.contains('.')) {
        _amount.text = _amount.text.split('.').first;
      }
    });
  }

  Future<void> _pickDate() async {
    final bounds = DatePickerBounds.clamped(
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: bounds.initialDate,
      firstDate: bounds.firstDate,
      lastDate: bounds.lastDate,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final amount = _parsedAmount;
    if (amount == null || _busy) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.createTransfer(
        direction: widget.direction,
        amount: _currency == Currency.mmk ? amount.roundToDouble() : amount,
        currency: _currency,
        date: _date,
        description: _note.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      // A Family-mode `no_family`: the app goes back to Personal and says why.
      if (e is ApiException && e.reported) return;
      setState(() {
        _busy = false;
        _error = transferErrorMessage(l, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final toFamily = widget.direction == TransferDirection.toFamily;
    final whole = _currency == Currency.mmk;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(toFamily ? l.moveToFamilyWallet : l.takeFromFamilyWallet, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            toFamily ? l.moveToFamilyHint : l.takeFromFamilyHint,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [for (final c in _kCurrencyOrder) _currencyPill(c, scheme)],
          ),
          const SizedBox(height: 12),
          TextField(
            key: TransferSheet.amountKey,
            controller: _amount,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.numberWithOptions(decimal: !whole),
            inputFormatters: [_AmountFormatter(whole: whole)],
            style: AppTheme.money(28, weight: FontWeight.w800, color: scheme.onSurface),
            decoration: InputDecoration(
              labelText: '${l.amountLabel} · ${_currency.name.toUpperCase()}',
              prefixText: '${_currency.symbol} ',
              hintText: '0',
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 12),
          InkWell(
            key: TransferSheet.dateKey,
            onTap: _busy ? null : _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outline),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_rounded, color: scheme.onSurface),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppDates.full(context, _date),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: TransferSheet.noteKey,
            controller: _note,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: l.descriptionLabel,
              hintText: l.descriptionHint,
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          Text(l.transferNotIncome, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.4)),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer, height: 1.4)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: TransferSheet.submitKey,
            onPressed: _busy || _parsedAmount == null ? null : _submit,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.transferMoveButton, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _currencyPill(Currency currency, ColorScheme scheme) {
    final selected = _currency == currency;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: TransferSheet.currencyKey(currency),
        onTap: _busy ? null : () => _setCurrency(currency),
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
      ),
    );
  }
}

/// Digits only for kyat (whole); up to two decimals otherwise; 12 digits at
/// most. An edit that doesn't fit is ignored.
class _AmountFormatter extends TextInputFormatter {
  _AmountFormatter({required this.whole});

  final bool whole;

  static final _wholePattern = RegExp(r'^\d{0,12}$');
  static final _decimalPattern = RegExp(r'^\d{0,12}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final ok = (whole ? _wholePattern : _decimalPattern).hasMatch(newValue.text);
    return ok ? newValue : oldValue;
  }
}
