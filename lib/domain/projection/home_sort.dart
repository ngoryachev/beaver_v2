import '../models/account.dart';
import '../models/amount_sort.dart';
import '../models/planned_op.dart';
import 'monthly_equivalent.dart';
import 'rate_table.dart';

/// Accounts by balance in [baseCurrency], signed: [AmountSort.desc] puts the
/// most money on top and an overdrawn account at the bottom.
List<Account> sortAccounts(
  Iterable<Account> accounts, {
  required RateTable rates,
  required String baseCurrency,
  required AmountSort direction,
}) => _sortBy(
  accounts,
  (account) => rates.convertMinor(
    account.balance,
    from: account.currencyCode,
    to: baseCurrency,
  ),
  direction,
);

/// Categories by the size of their monthly estimate — the figure in the group
/// header. By magnitude rather than with its sign: signed, «по убыванию» would
/// open with the salary and end with the largest expense, while the question
/// the sort answers is "where does the most money go".
///
/// [totals] is iterated in its own order, which is kept between equal values.
List<OpCategory> sortCategories(
  Map<OpCategory, MonthlyTotal> totals, {
  required AmountSort direction,
}) => _sortBy(
  totals.keys,
  (category) => totals[category]!.amountMinor.abs(),
  direction,
);

/// Operations by their amount in [baseCurrency] — what the tile shows next to
/// the original amount. [PlannedOp.amount] is never negative, so this too is a
/// sort by magnitude, income and expense alike.
List<PlannedOp> sortOps(
  Iterable<PlannedOp> ops, {
  required RateTable rates,
  required String baseCurrency,
  required AmountSort direction,
}) => _sortBy(
  ops,
  (op) =>
      rates.convertMinor(op.amount, from: op.currencyCode, to: baseCurrency),
  direction,
);

/// Stable sort by [key]. Items whose key is null — no rate to put them in the
/// base currency — go last in either direction: they have no place on the
/// scale, and flipping the sort should not bring them to the top.
List<T> _sortBy<T>(
  Iterable<T> items,
  int? Function(T) key,
  AmountSort direction,
) {
  final indexed = [
    for (final (index, item) in items.indexed) (index, item, key(item)),
  ];
  indexed.sort((a, b) {
    final (indexA, _, keyA) = a;
    final (indexB, _, keyB) = b;
    if (keyA == null || keyB == null) {
      if (keyA == keyB) return indexA.compareTo(indexB);
      return keyA == null ? 1 : -1;
    }
    final byKey = direction == AmountSort.asc
        ? keyA.compareTo(keyB)
        : keyB.compareTo(keyA);
    // `List.sort` is not stable; the original position breaks ties instead.
    return byKey != 0 ? byKey : indexA.compareTo(indexB);
  });
  return [for (final (_, item, _) in indexed) item];
}
