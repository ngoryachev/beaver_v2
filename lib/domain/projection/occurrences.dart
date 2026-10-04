import '../models/planned_op.dart';

/// Strips the time part so every date comparison is calendar-based. All
/// projection dates are local midnight.
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Number of days in [month] of [year].
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// [date] shifted by [days] calendar days, staying at local midnight.
///
/// Never use `Duration(days: n)` for this: a duration is exactly 24 h, but a
/// local day is 23 h or 25 h across a daylight-saving transition, so adding one
/// lands at 01:00 or 23:00 instead of midnight. The `DateTime` constructor
/// normalises an out-of-range day, which is what makes this calendar-correct.
DateTime addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// Whole calendar days from [from] to [to], ignoring any time component.
///
/// Reinterpreted in UTC so a 23- or 25-hour local day still counts as one day —
/// `to.difference(from).inDays` is off by one across a DST transition.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// Every date in `[from, to]` (inclusive, date-only) on which [op] fires.
///
/// Occurrences are anchored at `op.startDate`, so a monthly operation that
/// starts on the 31st falls back to the last day of shorter months — and
/// returns to the 31st afterwards, because the anchor day is never mutated.
List<DateTime> occurrencesBetween(PlannedOp op, DateTime from, DateTime to) {
  final start = dateOnly(op.startDate);
  final windowFrom = dateOnly(from);
  final windowTo = dateOnly(to);
  if (windowTo.isBefore(windowFrom)) return const [];

  // `end_date` caps the series; a start after the window end can never fire.
  final end = op.endDate == null
      ? windowTo
      : _earlier(dateOnly(op.endDate!), windowTo);
  if (end.isBefore(windowFrom) || end.isBefore(start)) return const [];

  final result = <DateTime>[];

  switch (op.schedule) {
    case Schedule.once:
      if (!start.isBefore(windowFrom) && !start.isAfter(end)) {
        result.add(start);
      }
    case Schedule.daily:
      var cursor = start.isBefore(windowFrom) ? windowFrom : start;
      while (!cursor.isAfter(end)) {
        result.add(cursor);
        cursor = addDays(cursor, 1);
      }
    case Schedule.weekly:
      result.addAll(_everyNDays(start, windowFrom, end, 7));
    case Schedule.biweekly:
      result.addAll(_everyNDays(start, windowFrom, end, 14));
    case Schedule.monthly:
      var index = 0;
      // Skip whole months at once instead of walking day by day.
      if (start.isBefore(windowFrom)) {
        index =
            (windowFrom.year - start.year) * 12 +
            (windowFrom.month - start.month);
        if (index < 0) index = 0;
        while (index > 0 && !_monthlyDate(start, index).isBefore(windowFrom)) {
          index--;
        }
      }
      while (true) {
        final date = _monthlyDate(start, index);
        if (date.isAfter(end)) break;
        if (!date.isBefore(windowFrom)) result.add(date);
        index++;
      }
    case Schedule.yearly:
      var year = start.year;
      if (windowFrom.year > year) year = windowFrom.year - 1;
      while (true) {
        final date = _yearlyDate(start, year);
        if (date.isAfter(end)) break;
        if (!date.isBefore(windowFrom) && !date.isBefore(start)) {
          result.add(date);
        }
        year++;
      }
  }

  return result;
}

/// Dates on a fixed [period]-day cadence anchored at [start], inside
/// `[windowFrom, end]`. Shared by `weekly` and `biweekly`, which differ only in
/// the period.
List<DateTime> _everyNDays(
  DateTime start,
  DateTime windowFrom,
  DateTime end,
  int period,
) {
  // Align to the first on-cycle day at or after the window start.
  var cursor = start;
  if (cursor.isBefore(windowFrom)) {
    final elapsed = daysBetween(start, windowFrom);
    final periods = (elapsed / period).ceil();
    cursor = addDays(start, periods * period);
  }
  final result = <DateTime>[];
  while (!cursor.isAfter(end)) {
    result.add(cursor);
    cursor = addDays(cursor, period);
  }
  return result;
}

/// [anchor] shifted forward by [monthsAhead] months, with the day clamped to
/// the target month's length (Jan 31 + 1 month → Feb 28/29).
DateTime _monthlyDate(DateTime anchor, int monthsAhead) {
  final totalMonths = anchor.month - 1 + monthsAhead;
  final year = anchor.year + totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final day = anchor.day <= daysInMonth(year, month)
      ? anchor.day
      : daysInMonth(year, month);
  return DateTime(year, month, day);
}

/// Same clamping as [_monthlyDate], for Feb 29 anchors in non-leap years.
DateTime _yearlyDate(DateTime anchor, int year) {
  final day = anchor.day <= daysInMonth(year, anchor.month)
      ? anchor.day
      : daysInMonth(year, anchor.month);
  return DateTime(year, anchor.month, day);
}

DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
