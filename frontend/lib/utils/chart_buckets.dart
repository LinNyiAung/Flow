import 'package:intl/intl.dart';
import 'package:frontend/utils/date_format.dart';

/// How the analytics bar charts group transactions over time.
enum ChartBucket {
  /// One bar per date; the axis shows the weekday over the day.
  dayWithWeekday,

  /// One bar per date.
  day,

  /// One bar per calendar month, all years together (January, February…).
  monthOfYear,

  /// One bar per month of a given year.
  month,

  /// One bar per year.
  year,
}

/// Keys and labels for [ChartBucket]s.
///
/// Keys sort in time order as plain strings and don't depend on the language
/// ("2026-11-10", "11", "2026-11", "2026"); only the labels are formatted, in
/// the app's language via [locale].
class ChartBuckets {
  ChartBuckets._();

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String keyFor(DateTime date, ChartBucket bucket) {
    switch (bucket) {
      case ChartBucket.dayWithWeekday:
      case ChartBucket.day:
        return '${date.year}-${_two(date.month)}-${_two(date.day)}';
      case ChartBucket.monthOfYear:
        return _two(date.month);
      case ChartBucket.month:
        return '${date.year}-${_two(date.month)}';
      case ChartBucket.year:
        return '${date.year}';
    }
  }

  /// The first moment of a bucket. For [ChartBucket.monthOfYear] the year is
  /// a placeholder (2000); only the month means anything.
  static DateTime dateOf(String key, ChartBucket bucket) {
    final parts = key.split('-').map(int.parse).toList();
    switch (bucket) {
      case ChartBucket.dayWithWeekday:
      case ChartBucket.day:
        return DateTime(parts[0], parts[1], parts[2]);
      case ChartBucket.monthOfYear:
        return DateTime(2000, parts[0]);
      case ChartBucket.month:
        return DateTime(parts[0], parts[1]);
      case ChartBucket.year:
        return DateTime(parts[0]);
    }
  }

  /// Short label under a bar: "Tue\n10 Nov", "10 Nov", "Nov", "Nov 2026", "2026".
  static String axisLabel(String key, ChartBucket bucket, {String? locale}) {
    final date = dateOf(key, bucket);
    switch (bucket) {
      case ChartBucket.dayWithWeekday:
        return '${DateFormat('EEE', locale).format(date)}\n${DateFormat('d MMM', locale).format(date)}';
      case ChartBucket.day:
        return DateFormat('d MMM', locale).format(date);
      case ChartBucket.monthOfYear:
        return DateFormat('MMM', locale).format(date);
      case ChartBucket.month:
        return DateFormat('MMM y', locale).format(date);
      case ChartBucket.year:
        return DateFormat('y', locale).format(date);
    }
  }

  /// Fuller label for a bar's tooltip: "Tue, 10 Nov 2026", "10 Nov 2026",
  /// "November", "November 2026", "2026".
  static String tooltipLabel(String key, ChartBucket bucket, {String? locale}) {
    final date = dateOf(key, bucket);
    switch (bucket) {
      case ChartBucket.dayWithWeekday:
        return '${DateFormat('EEE', locale).format(date)}, ${AppDates.fullIn(date, locale: locale)}';
      case ChartBucket.day:
        return AppDates.fullIn(date, locale: locale);
      case ChartBucket.monthOfYear:
        return DateFormat('MMMM', locale).format(date);
      case ChartBucket.month:
        return DateFormat('MMMM y', locale).format(date);
      case ChartBucket.year:
        return DateFormat('y', locale).format(date);
    }
  }

  /// Sums each item's amount per bucket, keys in time order.
  static Map<String, double> group<T>(
    Iterable<T> items,
    ChartBucket bucket, {
    required DateTime Function(T) dateOfItem,
    required double Function(T) amountOf,
  }) {
    final totals = <String, double>{};
    for (final item in items) {
      final key = keyFor(dateOfItem(item), bucket);
      totals[key] = (totals[key] ?? 0) + amountOf(item);
    }
    final keys = totals.keys.toList()..sort();
    return {for (final k in keys) k: totals[k]!};
  }
}
