import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/currency.dart';
import 'package:beaver_v2/domain/models/money.dart';
import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/projection/project_balance.dart';
import 'package:beaver_v2/domain/projection/rate_table.dart';
import 'package:flutter_test/flutter_test.dart';

/// `RateTable.convertMinor` returns `null` for two different reasons: a rate it
/// does not have, and a product it cannot represent. [projectBalance] only
/// reacts to the first — it asks `rates.missing(...)`, which hands back an empty
/// set when both rates are present. The amount is then left out of the total and
/// nothing on screen says so.
///
/// This is not a synthetic state. `Money.tryParse` deliberately accepts any
/// amount up to `Money.maxMinor`, so the app's own balance editor lets a user
/// type a figure its own conversion cannot carry at a perfectly ordinary rate.
void main() {
  Rate rate(String code, double value) => Rate(
    userId: 'u1',
    code: code,
    ratePerUsd: value,
    source: RateSource.auto,
    updatedAt: DateTime.utc(2026, 3, 1),
  );

  // Ordinary, believable rates: 90 ₽ to the dollar.
  final rates = RateTable.fromRates([rate('RUB', 90), rate('USD', 1)]);

  // 10 000 000 000 000,00 $ — absurd as a balance, but this is exactly what the
  // balance editor accepts and stores, because `Money.tryParse` only refuses
  // amounts past `Money.maxMinor`.
  final typed = Money.tryParse(
    '10000000000000,00',
    decimals: Currency.decimalsOf('USD'),
  );

  test('the balance editor accepts the amount in the first place', () {
    expect(
      typed,
      isNotNull,
      reason: 'otherwise this whole case is unreachable',
    );
    expect(rates.convertMinor(typed!.minor, from: 'USD', to: 'RUB'), isNull);
  });

  test('an unconvertible balance is flagged, not silently dropped', () {
    final result = projectBalance(
      accounts: [
        Account(
          id: 'a1',
          userId: 'u1',
          name: 'Счёт',
          currencyCode: 'USD',
          balance: typed!.minor,
        ),
      ],
      ops: const [],
      from: DateTime(2026, 3, 1),
      to: DateTime(2026, 3, 2),
      rates: rates,
      baseCurrency: 'RUB',
    );

    // Either it converts, or it says it could not. Reporting «Всего 0 ₽» with no
    // warning at all is the one outcome the UI cannot recover from.
    //
    // The reason is split across two sets — a rate that is absent versus an
    // amount too large for one that is present — because the UI offers a
    // different remedy for each. Silence in *both* is the failure.
    expect(
      result.startBalance == 0 &&
          result.missingRateCodes.isEmpty &&
          result.unconvertibleCodes.isEmpty,
      isFalse,
      reason:
          'startBalance=${result.startBalance}, '
          'missingRateCodes=${result.missingRateCodes}, '
          'unconvertibleCodes=${result.unconvertibleCodes}',
    );
  });

  test('an unconvertible operation is flagged, not silently dropped', () {
    final result = projectBalance(
      accounts: const [],
      ops: [
        PlannedOp(
          id: 'o1',
          userId: 'u1',
          title: 'Продажа',
          amount: typed!.minor,
          currencyCode: 'USD',
          kind: OpKind.income,
          schedule: Schedule.once,
          startDate: DateTime(2026, 3, 1),
        ),
      ],
      from: DateTime(2026, 3, 1),
      to: DateTime(2026, 3, 2),
      rates: rates,
      baseCurrency: 'RUB',
    );

    expect(
      result.endBalance == result.startBalance &&
          result.missingRateCodes.isEmpty &&
          result.unconvertibleCodes.isEmpty,
      isFalse,
      reason:
          'endBalance=${result.endBalance}, '
          'missingRateCodes=${result.missingRateCodes}, '
          'unconvertibleCodes=${result.unconvertibleCodes}',
    );
  });
}
