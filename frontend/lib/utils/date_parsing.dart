/// Helpers for reading and writing the API's dates.
///
/// There are three kinds of values:
///
/// * **Instants** (created_at, updated_at, generated_at, expires_at, ...):
///   real points in time, sent as UTC ISO with an offset. Use
///   [parseInstant], which converts to local time.
/// * **Local date-times** (transaction, transfer and recurring `date`, report
///   start/end): the person's own clock, sent with no offset, e.g.
///   `2026-11-18T23:40:00`. Use [parseWallClock] to read and
///   [toWallClockString] to write; both keep the year/month/day/hour/minute
///   fields as they are.
/// * **Calendar dates** (budget start/end, goal target date, recurrence end,
///   insight ranges): `2026-11-30`. Use [parseCalendarDate] (local midnight
///   of that day) and [toCalendarDateString].
library;

final RegExp _offsetSuffix = RegExp(r'(Z|[+-]\d{2}(:?\d{2})?)$', caseSensitive: false);

/// True when [value] has an explicit `Z` or `+hh:mm` / `-hh:mm` suffix in its
/// time component.
bool _hasOffset(String value) {
  final tIndex = value.indexOf(RegExp('[Tt ]'));
  if (tIndex == -1) return false;
  return _offsetSuffix.hasMatch(value.substring(tIndex + 1));
}

/// Parses an instant and returns it in local time. Values without an offset
/// are treated as UTC (legacy backend behaviour).
DateTime parseInstant(dynamic value) {
  if (value is DateTime) return value.toLocal();
  final s = value.toString().trim();
  final normalized = (_hasOffset(s) || !s.contains(RegExp('[Tt ]'))) ? s : '${s}Z';
  return DateTime.parse(normalized).toLocal();
}

DateTime? parseInstantOrNull(dynamic value) {
  if (value == null) return null;
  try {
    return parseInstant(value);
  } catch (_) {
    return null;
  }
}

/// Parses a local date-time: reads an offset-less string as local, drops any
/// offset without converting, and returns a local [DateTime] with exactly the
/// same calendar/time fields.
DateTime parseWallClock(dynamic value) {
  if (value is DateTime) {
    return DateTime(value.year, value.month, value.day, value.hour,
        value.minute, value.second, value.millisecond, value.microsecond);
  }
  var s = value.toString().trim();
  final tIndex = s.indexOf(RegExp('[Tt ]'));
  if (tIndex != -1) {
    final datePart = s.substring(0, tIndex + 1);
    final timePart = s.substring(tIndex + 1).replaceFirst(_offsetSuffix, '');
    s = '$datePart$timePart';
  }
  final parsed = DateTime.parse(s);
  if (!parsed.isUtc) return parsed;
  return DateTime(parsed.year, parsed.month, parsed.day, parsed.hour,
      parsed.minute, parsed.second, parsed.millisecond, parsed.microsecond);
}

DateTime? parseWallClockOrNull(dynamic value) {
  if (value == null) return null;
  try {
    return parseWallClock(value);
  } catch (_) {
    return null;
  }
}

final RegExp _calendarDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|[Tt ])');

/// Parses a calendar date (`2026-11-30`) as local midnight of that day. A
/// date-time string keeps its date part; its time and offset are ignored.
DateTime parseCalendarDate(String value) {
  final match = _calendarDate.firstMatch(value.trim());
  if (match == null) throw FormatException('Not a calendar date', value);
  return DateTime(int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!));
}

DateTime? parseCalendarDateOrNull(dynamic value) {
  if (value is! String) return null;
  try {
    return parseCalendarDate(value);
  } catch (_) {
    return null;
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// The local `yyyy-MM-dd` of [d] (an instant is first read on the phone's
/// clock).
String toCalendarDateString(DateTime d) {
  final local = d.isUtc ? d.toLocal() : d;
  return '${local.year.toString().padLeft(4, '0')}-${_two(local.month)}-${_two(local.day)}';
}

/// [d] as a local ISO date-time with no offset, e.g.
/// `2026-11-18T23:40:00.000` (an instant is first read on the phone's clock).
String toWallClockString(DateTime d) => (d.isUtc ? d.toLocal() : d).toIso8601String();

/// Whole calendar days from [from]'s date to [to]'s date (negative when [to]
/// is earlier). Times of day and DST shifts are ignored.
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
