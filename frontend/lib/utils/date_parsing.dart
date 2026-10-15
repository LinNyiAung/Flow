/// Helpers for parsing datetimes returned by the API.
///
/// The backend always tags datetimes with a UTC offset (e.g.
/// `2026-10-09T07:24:29.178000+00:00`). There are two kinds of values:
///
/// * **Instants** (created_at, updated_at, generated_at, expires_at, ...):
///   real points in time. Use [parseInstant], which converts to local time.
/// * **Wall-clock dates** (transaction date, budget start/end, goal target
///   date, recurrence end date, report start/end): the app stores the user's
///   local wall-clock time tagged as UTC. Use [parseWallClock], which keeps
///   the same year/month/day/hour/minute/second fields but returns a *local*
///   [DateTime], so display and comparisons behave like local dates.
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

/// Parses a wall-clock date: drops any UTC offset and returns a local
/// [DateTime] with exactly the same calendar/time fields.
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

/// Encodes a local wall-clock [DateTime] as a UTC-tagged ISO string with the
/// same fields (the format the backend stores wall-clock dates in).
String wallClockToUtcIso(DateTime d) => DateTime.utc(d.year, d.month, d.day,
        d.hour, d.minute, d.second, d.millisecond, d.microsecond)
    .toIso8601String();

/// Start of the given calendar day (00:00:00) as a UTC-tagged ISO string.
String startOfDayUtcIso(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).toIso8601String();

/// End of the given calendar day (23:59:59) as a UTC-tagged ISO string.
String endOfDayUtcIso(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day, 23, 59, 59).toIso8601String();
