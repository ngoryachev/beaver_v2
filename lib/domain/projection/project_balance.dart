import '../models/account.dart';
import '../models/planned_op.dart';
import 'occurrences.dart';
import 'rate_table.dart';

/// One operation firing on one date, already converted into the base currency.
class ProjectionEvent {
  final DateTime date;
  final PlannedOp op;

  /// Signed amount in minor units of the operation's own currency.
  final int amountMinor;

  /// Same amount in base currency minor units, or `null` when the rate is
  /// missing — the event is still listed so the UI can flag it.
  final int? baseAmountMinor;

  const ProjectionEvent({
    required this.date,
    required this.op,
    required this.amountMinor,
    required this.baseAmountMinor,
  });
}

/// A balance value on a given date, in base-currency minor units.
class ProjectionPoint {
  final DateTime date;
  final int balanceMinor;

  const ProjectionPoint(this.date, this.balanceMinor);
}

/// The forecast for one window, everything in base-currency minor units.
class ProjectionResult {
  /// Sum of the included account balances at `from`.
  final int startBalance;

  /// Balance after every event in the window has been applied.
  final int endBalance;

  /// One point per day of the window, `from` first.
  final List<ProjectionPoint> points;

  /// Every occurrence in the window, chronological.
  final List<ProjectionEvent> events;

  /// Lowest value across [points] (never above [startBalance]).
  final int minBalance;

  /// Date [minBalance] is first reached.
  final DateTime minDate;

  /// Currency codes that appear in the input but have no usable rate. Amounts
  /// in those currencies are excluded from the totals rather than counted as 0,
  /// so the UI can warn instead of quietly lying.
  final Set<String> missingRateCodes;

  const ProjectionResult({
    required this.startBalance,
    required this.endBalance,
    required this.points,
    required this.events,
    required this.minBalance,
    required this.minDate,
    required this.missingRateCodes,
  });
}

/// Projects the total balance day by day over `[from, to]`.
///
/// Pure: it reads the inputs and returns a result, never touching an account's
/// stored balance. Callers are expected to have already filtered [accounts] and
/// [ops] through the active scenario.
ProjectionResult projectBalance({
  required List<Account> accounts,
  required List<PlannedOp> ops,
  required DateTime from,
  required DateTime to,
  required RateTable rates,
  required String baseCurrency,
}) {
  final windowFrom = dateOnly(from);
  final windowTo = dateOnly(to);
  final effectiveTo = windowTo.isBefore(windowFrom) ? windowFrom : windowTo;
  final base = baseCurrency.toUpperCase();
  final missing = <String>{};

  var startBalance = 0;
  for (final account in accounts) {
    if (account.archived) continue;
    final converted = rates.convertMinor(
      account.balance,
      from: account.currencyCode,
      to: base,
    );
    if (converted == null) {
      missing.add(account.currencyCode.toUpperCase());
      continue;
    }
    startBalance += converted;
  }

  // Bucket occurrences by day so the daily walk below is a single pass.
  final events = <ProjectionEvent>[];
  final deltaByDay = <DateTime, int>{};
  for (final op in ops) {
    if (!op.enabled) continue;
    final dates = occurrencesBetween(op, windowFrom, effectiveTo);
    if (dates.isEmpty) continue;

    final signed = op.signedAmount;
    final converted = rates.convertMinor(
      signed,
      from: op.currencyCode,
      to: base,
    );
    if (converted == null) missing.add(op.currencyCode.toUpperCase());

    for (final date in dates) {
      events.add(
        ProjectionEvent(
          date: date,
          op: op,
          amountMinor: signed,
          baseAmountMinor: converted,
        ),
      );
      if (converted != null) {
        deltaByDay[date] = (deltaByDay[date] ?? 0) + converted;
      }
    }
  }

  events.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.op.title.compareTo(b.op.title);
  });

  final points = <ProjectionPoint>[];
  var running = startBalance;
  var minBalance = startBalance;
  var minDate = windowFrom;

  for (
    var day = windowFrom;
    !day.isAfter(effectiveTo);
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    running += deltaByDay[day] ?? 0;
    points.add(ProjectionPoint(day, running));
    if (running < minBalance) {
      minBalance = running;
      minDate = day;
    }
  }

  return ProjectionResult(
    startBalance: startBalance,
    endBalance: running,
    points: points,
    events: events,
    minBalance: minBalance,
    minDate: minDate,
    missingRateCodes: missing,
  );
}

/// Currencies the base currency is allowed to be: those of the non-archived
/// accounts. Order follows the accounts' own order, deduplicated.
List<String> baseCurrencyCandidates(List<Account> accounts) {
  final codes = <String>[];
  for (final account in accounts) {
    if (account.archived) continue;
    final code = account.currencyCode.toUpperCase();
    if (!codes.contains(code)) codes.add(code);
  }
  return codes;
}

/// Enforces the invariant "base currency is a currency of some non-archived
/// account". Falls back to the first candidate, or to [fallback] when the user
/// has no accounts at all.
String normalizeBaseCurrency(
  String baseCurrency,
  List<Account> accounts, {
  String fallback = 'RUB',
}) {
  final candidates = baseCurrencyCandidates(accounts);
  if (candidates.isEmpty) return baseCurrency.toUpperCase();
  final current = baseCurrency.toUpperCase();
  if (candidates.contains(current)) return current;
  return candidates.contains(fallback.toUpperCase())
      ? fallback.toUpperCase()
      : candidates.first;
}
