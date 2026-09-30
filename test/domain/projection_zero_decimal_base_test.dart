import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/projection/occurrences.dart';
import 'package:beaver_v2/domain/projection/project_balance.dart';
import 'package:beaver_v2/domain/projection/rate_table.dart';
import 'package:flutter_test/flutter_test.dart';

/// A whole projection in a base currency that has no minor units. Every amount
/// crosses the major/minor scale twice on the way in, so a factor of 100 slipping
/// in would show up as a total a hundred times too large or too small — and the
/// base currency is whatever account the user happens to have, so JPY is not a
/// hypothetical.
const _userId = 'u1';

Account _account(String id, String code, int balance) => Account(
  id: id,
  userId: _userId,
  name: id,
  currencyCode: code,
  balance: balance,
);

Rate _rate(String code, double perUsd) => Rate(
  userId: _userId,
  code: code,
  ratePerUsd: perUsd,
  source: RateSource.auto,
  updatedAt: DateTime.utc(2026),
);

void main() {
  // 1 USD = 100 ₽ = 150 ¥, so 1 000 ₽ is exactly 1 500 ¥.
  final rates = RateTable.fromRates([_rate('RUB', 100), _rate('JPY', 150)]);
  final from = DateTime(2026, 3, 1);

  group('projectBalance with a zero-decimal base currency', () {
    test('sums a foreign account into whole yen', () {
      final result = projectBalance(
        accounts: [
          // 1 000 ₽ and 5 000 ¥.
          _account('a1', 'RUB', 100000),
          _account('a2', 'JPY', 5000),
        ],
        ops: const [],
        from: from,
        to: from,
        rates: rates,
        baseCurrency: 'JPY',
      );

      expect(result.startBalance, 6500);
      expect(result.missingRateCodes, isEmpty);
    });

    test('applies a foreign operation in whole yen, once per day', () {
      final result = projectBalance(
        accounts: [_account('a2', 'JPY', 5000)],
        ops: [
          PlannedOp(
            id: 'op1',
            userId: _userId,
            // 100 ₽ a day — 150 ¥ a day in the base currency.
            title: 'Обед',
            amount: 10000,
            currencyCode: 'RUB',
            kind: OpKind.expense,
            schedule: Schedule.daily,
            startDate: from,
            endDate: addDays(from, 9),
          ),
        ],
        from: from,
        to: addDays(from, 9),
        rates: rates,
        baseCurrency: 'JPY',
      );

      expect(result.events.length, 10);
      expect(result.events.first.baseAmountMinor, -150);
      expect(result.endBalance, 5000 - 10 * 150);
      expect(result.minBalance, 5000 - 10 * 150);
    });

    test('the reverse direction is just as exact', () {
      // 5 000 ¥ back into roubles: 5 000 / 150 * 100 = 3 333,33 ₽.
      final result = projectBalance(
        accounts: [_account('a2', 'JPY', 5000)],
        ops: const [],
        from: from,
        to: from,
        rates: rates,
        baseCurrency: 'RUB',
      );

      expect(result.startBalance, 333333);
    });
  });
}
