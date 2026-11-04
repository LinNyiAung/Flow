/// The shortest range a custom insight accepts, in days (both ends count).
const int customInsightMinDays = 7;

/// The longest instruction, in characters after trimming.
const int customInstructionMaxLength = 300;

enum CustomQuickRange { last30Days, last3Months, thisYear }

/// A start and an end date (local, date-only), both included.
class DateRangeChoice {
  final DateTime start;
  final DateTime end;

  const DateRangeChoice(this.start, this.end);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The range a quick button picks, ending [today].
DateRangeChoice quickRange(CustomQuickRange r, DateTime today) {
  final t = _day(today);
  switch (r) {
    case CustomQuickRange.last30Days:
      return DateRangeChoice(DateTime(t.year, t.month, t.day - 29), t);
    case CustomQuickRange.last3Months:
      return DateRangeChoice(DateTime(t.year, t.month - 3, t.day + 1), t);
    case CustomQuickRange.thisYear:
      return DateRangeChoice(DateTime(t.year, 1, 1), t);
  }
}

enum CustomRangeProblem { endBeforeStart, tooShort, tooLong, inFuture }

/// Why start..end cannot be sent, or null when it is fine. The same rules as
/// the server, checked in its order: end not before start, at least
/// [customInsightMinDays] days, not after [today], under 12 months (the end
/// must be before the same date one year after the start).
CustomRangeProblem? customRangeProblem(DateTime start, DateTime end, DateTime today) {
  final s = _day(start);
  final e = _day(end);
  final t = _day(today);
  if (e.isBefore(s)) return CustomRangeProblem.endBeforeStart;
  // Calendar-day difference (immune to DST hours).
  final days = DateTime.utc(e.year, e.month, e.day)
          .difference(DateTime.utc(s.year, s.month, s.day))
          .inDays +
      1;
  if (days < customInsightMinDays) return CustomRangeProblem.tooShort;
  if (e.isAfter(t)) return CustomRangeProblem.inFuture;
  if (!e.isBefore(DateTime(s.year + 1, s.month, s.day))) return CustomRangeProblem.tooLong;
  return null;
}
