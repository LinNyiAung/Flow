import '../models/transaction.dart';
import '../models/user.dart';

/// Last-7-days spending for Home's "Spending pace" card, bucketed by calendar
/// day and kept per currency (amounts in different currencies are never
/// added together).
class SpendingPace {
  SpendingPace._(this.days, this._totals);

  /// The 7 calendar days shown, oldest first; the last one is today.
  final List<DateTime> days;
  final Map<Currency, List<double>> _totals;

  /// Spending per day in [currency], aligned with [days].
  List<double> totalsFor(Currency currency) =>
      _totals[currency] ?? List<double>.filled(days.length, 0);

  /// Currencies the chart can show: the ones with spending in the window,
  /// [defaultCurrency] first when it has any. With no spending at all, just
  /// [defaultCurrency].
  List<Currency> currencyOptions(Currency defaultCurrency) {
    final withSpending = Currency.values.where(_totals.containsKey).toList();
    if (withSpending.isEmpty) return [defaultCurrency];
    if (withSpending.remove(defaultCurrency)) withSpending.insert(0, defaultCurrency);
    return withSpending;
  }
}

/// Buckets [transactions] (outflows only) into the 7 days ending on [today].
/// Transaction dates are wall-clock values, so the day is read from their
/// date fields directly.
SpendingPace buildSpendingPace(List<Transaction> transactions, {required DateTime today}) {
  final start = DateTime(today.year, today.month, today.day);
  final days = List.generate(7, (i) => DateTime(start.year, start.month, start.day - 6 + i));
  final totals = <Currency, List<double>>{};
  for (final t in transactions) {
    if (t.type != TransactionType.outflow) continue;
    final index = days.indexOf(DateTime(t.date.year, t.date.month, t.date.day));
    if (index == -1) continue;
    totals.putIfAbsent(t.currency, () => List<double>.filled(7, 0))[index] += t.amount;
  }
  return SpendingPace._(days, totals);
}
