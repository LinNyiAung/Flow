import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/localization_service.dart';

/// Why a user-entered amount was rejected.
enum AmountInputError {
  /// Not a number (or more than two decimals).
  invalid,

  /// Commas that are neither a decimal comma nor valid thousands grouping
  /// (e.g. "1,5000", "12,345,67"): we can't tell what was meant.
  ambiguous,

  /// A valid number that is zero.
  notPositive,
}

/// Result of [parseAmountInput]: either [value] or [error] is set.
class AmountInput {
  final double? value;
  final AmountInputError? error;

  const AmountInput.value(double this.value) : error = null;
  const AmountInput.error(AmountInputError this.error) : value = null;
}

final RegExp _plainAmount = RegExp(r'^\d+(\.\d{1,2})?$');
final RegExp _decimalComma = RegExp(r'^(\d+),(\d{1,2})$');
final RegExp _groupedAmount = RegExp(r'^\d{1,3}(,\d{3})+(\.\d{1,2})?$');

/// Parses a user-entered amount (> 0, at most two decimals).
///
/// * A single comma followed by exactly 1–2 digits, with no dot, is a
///   decimal separator: "12,50" → 12.5, "12,5" → 12.5.
/// * Otherwise commas must be valid thousands grouping: "1,500" → 1500,
///   "1,500.50" → 1500.5.
/// * Anything else with commas ("1,5000", "1,50.5") is [AmountInputError.ambiguous].
AmountInput parseAmountInput(String input) {
  final text = input.trim();
  String normalized;
  if (_plainAmount.hasMatch(text)) {
    normalized = text;
  } else if (_decimalComma.hasMatch(text)) {
    normalized = text.replaceFirst(',', '.');
  } else if (_groupedAmount.hasMatch(text)) {
    normalized = text.replaceAll(',', '');
  } else {
    return AmountInput.error(text.contains(',') && RegExp(r'^[\d.,]+$').hasMatch(text)
        ? AmountInputError.ambiguous
        : AmountInputError.invalid);
  }
  final value = double.tryParse(normalized);
  if (value == null) return const AmountInput.error(AmountInputError.invalid);
  if (value <= 0) return const AmountInput.error(AmountInputError.notPositive);
  return AmountInput.value(value);
}

/// Parses a user-entered amount; null unless it is a number > 0 with at
/// most two decimals (see [parseAmountInput] for the comma rules).
double? parsePositiveAmount(String input) => parseAmountInput(input).value;

/// Asks for an amount (> 0) for an AI-extracted item whose amount could not
/// be read. Returns null when cancelled.
Future<double?> showAmountEntryDialog(
  BuildContext context, {
  required Currency currency,
  double? initialAmount,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _AmountEntryDialog(
      currency: currency,
      initialAmount: initialAmount,
    ),
  );
}

class _AmountEntryDialog extends StatefulWidget {
  final Currency currency;
  final double? initialAmount;

  const _AmountEntryDialog({required this.currency, this.initialAmount});

  @override
  State<_AmountEntryDialog> createState() => _AmountEntryDialogState();
}

class _AmountEntryDialogState extends State<_AmountEntryDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialAmount;
    _controller = TextEditingController(
      text: initial != null && initial > 0
          ? (initial == initial.roundToDouble()
              ? initial.toStringAsFixed(0)
              : initial.toStringAsFixed(2))
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final localizations = AppLocalizations.of(context);
    final result = parseAmountInput(_controller.text);
    final value = result.value;
    if (value == null) {
      setState(() {
        _errorText = switch (result.error) {
          AmountInputError.notPositive => localizations.validationAmountPositive,
          AmountInputError.ambiguous => localizations.amountAmbiguousFormat,
          _ => localizations.validationAmountInvalid,
        };
      });
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(localizations.amountLabel),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(
          prefixText: '${widget.currency.symbol} ',
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.dialogCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(localizations.save),
        ),
      ],
    );
  }
}
