import 'package:frontend/utils/money.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/transaction.dart';
import '../models/user.dart';
import '../services/localization_service.dart';
import '../services/responsive_helper.dart';
import '../utils/date_locale.dart';
import '../utils/spending_pace.dart';


/// Home's "Spending pace" card: last-7-days spending as 7 bars, one currency
/// at a time. Tapping or dragging across the bars selects a day; the line
/// above the bars shows that day's total and links to its transactions.
class SpendingPaceCard extends StatefulWidget {
  const SpendingPaceCard({
    super.key,
    required this.outflows,
    required this.defaultCurrency,
    this.today,
    this.onSeeTransactions,
  });

  /// The last 7 days' outflows (other transactions are ignored).
  final List<Transaction> outflows;
  final Currency defaultCurrency;

  /// Defaults to now; injectable for tests.
  final DateTime? today;

  /// Opens the transactions for [day] in [currency]; no link when null.
  final void Function(DateTime day, Currency currency)? onSeeTransactions;

  @override
  State<SpendingPaceCard> createState() => _SpendingPaceCardState();
}

class _SpendingPaceCardState extends State<SpendingPaceCard> {
  static const _today = 6;

  int _selected = _today;
  Currency? _currency;

  @override
  void didUpdateWidget(SpendingPaceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // New data (a refresh, or coming back from the transactions list) starts
    // again from today.
    if (!identical(oldWidget.outflows, widget.outflows)) _selected = _today;
  }

  String _dayLabel(BuildContext context, DateTime day, bool isToday) {
    if (isToday) return AppLocalizations.of(context).todayLabel;
    // The app's "10 Nov" day, with the weekday in front.
    return DateFormat('EEE, d MMM', dateLocaleOf(context)).format(day);
  }

  void _select(int index) {
    final clamped = index.clamp(0, _today);
    if (clamped != _selected) setState(() => _selected = clamped);
  }

  void _selectAt(double dx, double width) => _select((dx / (width / 7)).floor());

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final responsive = ResponsiveHelper(context);

    final pace = buildSpendingPace(widget.outflows, today: widget.today ?? DateTime.now());
    final options = pace.currencyOptions(widget.defaultCurrency);
    final currency = options.contains(_currency) ? _currency! : options.first;
    final totals = pace.totalsFor(currency);
    final maxTotal = totals.fold<double>(0, (max, v) => v > max ? v : max);

    String amountText(double total) => total > 0
        ? formatMoney(total, currency)
        : localizations.nothingSpent;

    final selectedDay = pace.days[_selected];
    final selectedTotal = totals[_selected];

    return Card(
      child: Padding(
        padding: responsive.padding(left: 18, right: 18, top: 18, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Full width, so spaceBetween can push the chips to the right
            // edge (a bare Wrap is only as wide as its content); they still
            // wrap under the title when the row is too narrow.
            SizedBox(
              width: double.infinity,
              child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: responsive.sp8,
              runSpacing: responsive.sp6,
              children: [
                Text(
                  localizations.spendingPace,
                  style: TextStyle(
                    fontSize: responsive.fs16,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                if (options.length > 1)
                  Wrap(
                    spacing: responsive.sp6,
                    children: [
                      for (final c in options)
                        ChoiceChip(
                          key: ValueKey('spending-pace-currency-${c.name}'),
                          label: Text(c.symbol),
                          tooltip: c.displayName,
                          selected: c == currency,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _currency = c),
                        ),
                    ],
                  ),
              ],
              ),
            ),
            SizedBox(height: responsive.sp8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: responsive.sp8,
              children: [
                Text(
                  '${_dayLabel(context, selectedDay, _selected == _today)} · ${amountText(selectedTotal)}',
                  style: TextStyle(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                if (selectedTotal > 0 && widget.onSeeTransactions != null)
                  TextButton(
                    onPressed: () => widget.onSeeTransactions!(selectedDay, currency),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: responsive.sp8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(localizations.seeTransactions),
                  ),
              ],
            ),
            SizedBox(height: responsive.sp12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _selectAt(d.localPosition.dx, width),
                  onHorizontalDragStart: (d) => _selectAt(d.localPosition.dx, width),
                  onHorizontalDragUpdate: (d) => _selectAt(d.localPosition.dx, width),
                  child: SizedBox(
                    height: 78,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List.generate(7, (i) {
                        final isSelected = i == _selected;
                        final ratio = maxTotal > 0 ? (totals[i] / maxTotal) : 0.0;
                        final barHeight = totals[i] > 0 ? (10 + ratio * 68) : 4.0;
                        return Expanded(
                          child: Semantics(
                            key: ValueKey('spending-pace-bar-$i'),
                            container: true,
                            button: true,
                            selected: isSelected,
                            label: '${_dayLabel(context, pace.days[i], i == _today)}, ${amountText(totals[i])}',
                            onTap: () => _select(i),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: responsive.spacing(mobile: 2.5),
                              ),
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  height: barHeight,
                                  decoration: BoxDecoration(
                                    color: isSelected ? scheme.primary : scheme.secondaryContainer,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                );
              },
            ),
            SizedBox(height: responsive.sp8),
            ExcludeSemantics(
              child: Row(
                children: pace.days
                    .map(
                      (d) => Expanded(
                        child: Text(
                          localizations.weekdayInitial(d.weekday),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: responsive.fs11,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
