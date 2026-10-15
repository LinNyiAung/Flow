/// Arguments for `showDatePicker` that always satisfy its assertions
/// (`firstDate <= initialDate <= lastDate`, compared as calendar days).
///
/// Passing e.g. an overdue goal's target date as `initialDate` with
/// `firstDate: DateTime.now()` throws inside `showDatePicker` and the
/// picker never opens; [DatePickerBounds.clamped] moves the initial date
/// into range instead (and widens `lastDate` if it is before `firstDate`).
///
/// All three dates are returned as local midnight of their calendar day
/// (a UTC-tagged wall-clock date keeps its year/month/day), so mixing UTC
/// and local inputs cannot shift a bound by a day.
class DatePickerBounds {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const DatePickerBounds._(this.initialDate, this.firstDate, this.lastDate);

  factory DatePickerBounds.clamped({
    required DateTime? initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    final first = _day(firstDate);
    var last = _day(lastDate);
    if (last.isBefore(first)) last = first;
    var initial = _day(initialDate ?? first);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    return DatePickerBounds._(initial, first, last);
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// The later of [a] and [b].
DateTime laterDate(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
