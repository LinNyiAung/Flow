import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:frontend/utils/date_locale.dart';

/// The app's one set of user-visible date formats. Month names follow the
/// app's language (Myanmar month names in Myanmar, via [dateLocaleOf]).
///
/// Only for dates people read. Dates sent to the server keep their own
/// fixed formats, and relative times ("10m ago") stay as they are.
///
/// Each format has a `BuildContext` form for widgets and a `locale` form
/// (pure, for models and tests).
class AppDates {
  AppDates._();

  /// "10 Nov"; "10 Nov 2025" when [date] isn't in [now]'s year.
  static String compactDayIn(DateTime date, {String? locale, DateTime? now}) {
    final current = now ?? DateTime.now();
    return date.year == current.year
        ? DateFormat('d MMM', locale).format(date)
        : fullIn(date, locale: locale);
  }

  /// "10 Nov 2026".
  static String fullIn(DateTime date, {String? locale}) => DateFormat('d MMM y', locale).format(date);

  /// "10 Nov 2026, 7:57 AM".
  static String dateTimeIn(DateTime date, {String? locale}) =>
      '${fullIn(date, locale: locale)}, ${DateFormat('h:mm a', locale).format(date)}';

  /// "1 Nov – 30 Nov 2026"; both years when they differ
  /// ("20 Dec 2025 – 19 Jan 2026").
  static String rangeIn(DateTime start, DateTime end, {String? locale}) {
    final from = start.year == end.year ? DateFormat('d MMM', locale).format(start) : fullIn(start, locale: locale);
    return '$from – ${fullIn(end, locale: locale)}';
  }

  static String compactDay(BuildContext context, DateTime date, {DateTime? now}) =>
      compactDayIn(date, locale: dateLocaleOf(context), now: now);

  static String full(BuildContext context, DateTime date) => fullIn(date, locale: dateLocaleOf(context));

  static String dateTime(BuildContext context, DateTime date) => dateTimeIn(date, locale: dateLocaleOf(context));

  static String range(BuildContext context, DateTime start, DateTime end) =>
      rangeIn(start, end, locale: dateLocaleOf(context));
}
