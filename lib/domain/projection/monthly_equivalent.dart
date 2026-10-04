import '../models/money.dart';
import '../models/planned_op.dart';
import 'occurrences.dart';
import 'rate_table.dart';

/// How many times a repeating operation fires in an average month.
///
/// Deliberately an average, not a count of real dates: a collapsed category
/// header answers "how much does this cost me a month", and 4.35 weeks is a
/// better answer there than "4 in February, 5 in March". [Schedule.once] has no
/// cadence at all — see [monthlyTotal], which counts it only in its own month.
double monthlyFactor(Schedule schedule) => switch (schedule) {
  Schedule.once => 0,
  // 365.25 / 12 days, / 7 weeks, / 14 days.
  Schedule.daily => 30.44,
  Schedule.weekly => 4.35,
  Schedule.biweekly => 2.17,
  Schedule.monthly => 1,
  Schedule.yearly => 1 / 12,
};

/// The monthly estimate for a set of operations, in base-currency minor units.
class MonthlyTotal {
  /// Signed: negative when the expenses outweigh the income.
  final int amountMinor;

  /// At least one operation was left out because its amount could not be
  /// expressed in the base currency — almost always a missing rate, or else a
  /// sum too large to hold. The figure is then a partial one, and the UI has to
  /// say so rather than pass it off as the whole truth.
  final bool partial;

  const MonthlyTotal({required this.amountMinor, required this.partial});
}

/// Sums [ops] into a per-month figure in [baseCurrency].
///
/// Disabled operations are skipped: they do not reach the forecast either.
/// A [Schedule.once] operation counts in full when its date falls in [today]'s
/// month and not at all otherwise, and a repeating one is skipped once it has
/// not started yet or its `end_date` is already past — an estimate of a series
/// that cannot fire this month is zero, not an average.
MonthlyTotal monthlyTotal({
  required Iterable<PlannedOp> ops,
  required RateTable rates,
  required String baseCurrency,
  required DateTime today,
}) {
  final monthStart = DateTime(today.year, today.month);
  final monthEnd = DateTime(
    today.year,
    today.month,
    daysInMonth(today.year, today.month),
  );

  var total = 0.0;
  var partial = false;

  for (final op in ops) {
    if (!op.enabled) continue;

    final start = dateOnly(op.startDate);
    final end = op.endDate == null ? null : dateOnly(op.endDate!);
    if (start.isAfter(monthEnd)) continue;
    if (end != null && end.isBefore(monthStart)) continue;

    final factor = op.schedule == Schedule.once
        ? (start.isBefore(monthStart) ? 0.0 : 1.0)
        : monthlyFactor(op.schedule);
    if (factor == 0) continue;

    final converted = rates.convertMinor(
      op.signedAmount,
      from: op.currencyCode,
      to: baseCurrency,
    );
    if (converted == null) {
      partial = true;
      continue;
    }
    total += converted * factor;
  }

  // The same ceiling `RateTable.convertMinor` enforces: a sum past it cannot be
  // held exactly on the web, where an `int` is a double, and `.round()` would
  // throw on a non-finite one.
  if (!total.isFinite || total.abs() > Money.maxMinor) {
    return MonthlyTotal(amountMinor: 0, partial: true);
  }
  return MonthlyTotal(amountMinor: total.round(), partial: partial);
}
