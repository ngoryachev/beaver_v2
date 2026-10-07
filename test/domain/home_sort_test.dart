import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/amount_sort.dart';
import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/projection/home_sort.dart';
import 'package:beaver_v2/domain/projection/monthly_equivalent.dart';
import 'package:beaver_v2/domain/projection/rate_table.dart';
import 'package:flutter_test/flutter_test.dart';

/// The by-amount sorts of the home screen: accounts by signed balance,
/// categories and operations by magnitude, anything without a rate last.
Account _account(String id, int balance, {String code = 'RUB'}) => Account(
  id: id,
  userId: 'u1',
  name: id,
  currencyCode: code,
  balance: balance,
);

PlannedOp _op(
  String id,
  int amount, {
  OpKind kind = OpKind.expense,
  String code = 'RUB',
}) => PlannedOp(
  id: id,
  userId: 'u1',
  title: id,
  amount: amount,
  currencyCode: code,
  kind: kind,
  schedule: Schedule.monthly,
  startDate: DateTime(2026, 1, 1),
);

Rate _rate(String code, double perUsd) => Rate(
  userId: 'u1',
  code: code,
  ratePerUsd: perUsd,
  source: RateSource.auto,
  updatedAt: DateTime.utc(2026),
);

// 1 USD = 90 RUB = 0.9 EUR, so 1 EUR = 100 RUB.
final _rates = RateTable.fromRates([
  _rate('RUB', 90),
  _rate('EUR', 0.9),
]);

List<String> _ids(Iterable<Object> items) => [
  for (final item in items)
    switch (item) {
      Account(:final id) => id,
      PlannedOp(:final id) => id,
      _ => '$item',
    },
];

void main() {
  group('sortAccounts', () {
    final accounts = [
      _account('small', 1000),
      _account('overdrawn', -5000),
      // 20 € = 2 000 ₽: larger than «small» only once converted.
      _account('euro', 2000, code: 'EUR'),
      _account('no-rate', 999999, code: 'GBP'),
    ];

    List<String> sorted(AmountSort direction) => _ids(
      sortAccounts(
        accounts,
        rates: _rates,
        baseCurrency: 'RUB',
        direction: direction,
      ),
    );

    test('descending: most money first, by the base-currency value', () {
      expect(sorted(AmountSort.desc), ['euro', 'small', 'overdrawn', 'no-rate']);
    });

    test('ascending: the overdrawn account first', () {
      expect(sorted(AmountSort.asc), ['overdrawn', 'small', 'euro', 'no-rate']);
    });

    test('equal balances keep their original order', () {
      final tied = [_account('b', 100), _account('a', 100)];
      for (final direction in AmountSort.values) {
        expect(
          _ids(
            sortAccounts(
              tied,
              rates: _rates,
              baseCurrency: 'RUB',
              direction: direction,
            ),
          ),
          ['b', 'a'],
        );
      }
    });
  });

  group('sortOps', () {
    final ops = [
      _op('rent', 4000000),
      _op('salary', 20000000, kind: OpKind.income),
      // 100 € = 10 000 ₽.
      _op('hosting', 10000, code: 'EUR'),
      _op('no-rate', 1, code: 'GBP'),
    ];

    List<String> sorted(AmountSort direction) => _ids(
      sortOps(ops, rates: _rates, baseCurrency: 'RUB', direction: direction),
    );

    test('by magnitude in the base currency, income and expense alike', () {
      expect(sorted(AmountSort.desc), ['salary', 'rent', 'hosting', 'no-rate']);
      expect(sorted(AmountSort.asc), ['hosting', 'rent', 'salary', 'no-rate']);
    });
  });

  group('sortCategories', () {
    final totals = {
      OpCategory.food: const MonthlyTotal(amountMinor: -1500000),
      OpCategory.housing: const MonthlyTotal(amountMinor: -4000000),
      OpCategory.health: const MonthlyTotal(amountMinor: -1500000),
      OpCategory.salary: const MonthlyTotal(amountMinor: 20000000),
    };

    test('by the magnitude of the monthly estimate', () {
      expect(sortCategories(totals, direction: AmountSort.desc), [
        OpCategory.salary,
        OpCategory.housing,
        OpCategory.food,
        OpCategory.health,
      ]);
    });

    test('ties keep the given order in both directions', () {
      expect(sortCategories(totals, direction: AmountSort.asc), [
        OpCategory.food,
        OpCategory.health,
        OpCategory.housing,
        OpCategory.salary,
      ]);
    });
  });

  test('AmountSort reads an unknown wire value as descending', () {
    expect(AmountSort.fromWire(null), AmountSort.desc);
    expect(AmountSort.fromWire('sideways'), AmountSort.desc);
    expect(AmountSort.fromWire('asc'), AmountSort.asc);
    expect(AmountSort.asc.toggled, AmountSort.desc);
  });
}
