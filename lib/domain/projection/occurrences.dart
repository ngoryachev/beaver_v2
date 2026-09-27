import '../models/planned_op.dart';

/// Strips the time part so every date comparison is calendar-based. All
/// projection dates are local midnight.
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Number of days in [month] of [year].
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

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
        cursor = cursor.add(const Duration(days: 1));
      }
    case Schedule.weekly:
      // Align to the first on-cycle day at or after the window start.
      var cursor = start;
      if (cursor.isBefore(windowFrom)) {
        final elapsed = windowFrom.difference(cursor).inDays;
        final periods = (elapsed / 7).ceil();
        cursor = _addDays(start, periods * 7);
      }
      while (!cursor.isAfter(end)) {
        result.add(cursor);
        cursor = _addDays(cursor, 7);
      }
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

/// Adds whole days without letting DST shifts move the calendar date.
DateTime _addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
