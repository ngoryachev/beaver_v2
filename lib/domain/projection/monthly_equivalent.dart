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

  /// At least one operation was left out because its currency has no usable
  /// rate. Kept apart from [unconvertible] for the same reason
  /// `ProjectionResult` keeps `missingRateCodes` and `unconvertibleCodes`
  /// apart: telling the user a rate is missing when one is set sends them to
  /// fix the wrong thing.
  final bool missingRate;

  /// At least one amount — or the sum itself — has a rate but is past what can
  /// be expressed in the base currency.
  final bool unconvertible;

  const MonthlyTotal({
    required this.amountMinor,
    this.missingRate = false,
    this.unconvertible = false,
  });

  /// Something was left out, so the figure is less than the whole truth and the
  /// UI has to say so.
  bool get partial => missingRate || unconvertible;
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
  var missingRate = false;
  var unconvertible = false;

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
      // The two reasons `convertMinor` gives up, told apart the same way
      // `AccountCard` tells them apart: no rate to convert with, or an amount
      // too large to express with the rate there is.
      if (rates.has(op.currencyCode) && rates.has(baseCurrency)) {
        unconvertible = true;
      } else {
        missingRate = true;
      }
      continue;
    }
    total += converted * factor;
  }

  // The same ceiling `RateTable.convertMinor` enforces: a sum past it cannot be
  // held exactly on the web, where an `int` is a double, and `.round()` would
  // throw on a non-finite one.
  if (!total.isFinite || total.abs() > Money.maxMinor) {
    return MonthlyTotal(
      amountMinor: 0,
      missingRate: missingRate,
      unconvertible: true,
    );
  }
  return MonthlyTotal(
    amountMinor: total.round(),
    missingRate: missingRate,
    unconvertible: unconvertible,
  );
}
