import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:frontend/models/custom_insight.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/localization_service.dart';

/// The most top-spending categories a card lists.
const int customInsightMaxTopCategories = 5;

final NumberFormat _amountFormat = NumberFormat('#,##0.00', 'en_US');

/// "$1,250.00", "-K500.00": the amount with its currency symbol (the code for
/// a currency the app has no symbol for).
String customInsightMoney(String currency, double amount) {
  final code = currency.toLowerCase();
  final known = Currency.values.where((c) => c.name == code).firstOrNull;
  final symbol = known?.symbol ?? '${currency.toUpperCase()} ';
  final text = '$symbol${_amountFormat.format(amount.abs())}';
  return amount < 0 ? '-$text' : text;
}

/// "+12.5%" / "-3.0%".
String _signedPercent(double pct) => '${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}%';

/// One card per currency with the report's figures: income, spending, net,
/// each change against the previous period, and the top spending categories.
class CustomInsightFigureCards extends StatelessWidget {
  const CustomInsightFigureCards(this.figures, {super.key});

  final CustomInsightFigures figures;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < figures.currencies.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _CurrencyCard(figures.currencies[i]),
        ],
      ],
    );
  }
}

class _CurrencyCard extends StatelessWidget {
  const _CurrencyCard(this.data);

  final CurrencyFigures data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final top = data.topCategories.take(customInsightMaxTopCategories).toList();

    Widget row(String label, double amount, {double? changePct, bool showChange = true, Color? color}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                  ),
                ),
                Text(
                  customInsightMoney(data.currency, amount),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color ?? scheme.onSurface),
                ),
              ],
            ),
            if (showChange)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  changePct == null
                      ? l.customReportNoPrevious
                      : '${_signedPercent(changePct)} ${l.customReportVsPrevious}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      );
    }

    return Card(
      key: Key('custom-figures-${data.currency.toLowerCase()}'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.currency.toUpperCase(),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.tertiary),
            ),
            const SizedBox(height: 6),
            row(l.customReportIncome, data.income, changePct: data.incomeChangePct),
            row(l.customReportSpending, data.spending, changePct: data.spendingChangePct),
            row(l.customReportNet, data.net, showChange: false, color: data.net < 0 ? scheme.error : scheme.primary),
            if (top.isNotEmpty) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: 12),
              Text(
                l.customReportTopSpending,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              for (final c in top)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.subCategory.isEmpty ? c.mainCategory : '${c.mainCategory} · ${c.subCategory}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: scheme.onSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        customInsightMoney(data.currency, c.amount),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
