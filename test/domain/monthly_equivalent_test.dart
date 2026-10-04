import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/projection/monthly_equivalent.dart';
import 'package:beaver_v2/domain/projection/rate_table.dart';
import 'package:flutter_test/flutter_test.dart';

/// The figure a collapsed category header shows. It is an estimate by design —
/// 30.44 days and 4.35 weeks a month — so these tests pin the estimate down
/// rather than any real calendar.
PlannedOp _op({
  required int amount,
  OpKind kind = OpKind.expense,
  Schedule schedule = Schedule.monthly,
  String code = 'RUB',
  DateTime? startDate,
  DateTime? endDate,
  bool enabled = true,
}) => PlannedOp(
  id: 'op1',
  userId: 'u1',
  title: 'Тест',
  amount: amount,
  currencyCode: code,
  kind: kind,
  schedule: schedule,
  startDate: startDate ?? DateTime(2026, 1, 1),
  endDate: endDate,
  enabled: enabled,
);

Rate _rate(String code, double perUsd) => Rate(
  userId: 'u1',
  code: code,
  ratePerUsd: perUsd,
  source: RateSource.auto,
  updatedAt: DateTime.utc(2026),
);

final _today = DateTime(2026, 3, 15);

MonthlyTotal _total(
  List<PlannedOp> ops, {
  List<Rate> rates = const [],
  String baseCurrency = 'RUB',
  DateTime? today,
}) => monthlyTotal(
  ops: ops,
  rates: RateTable.fromRates(rates),
  baseCurrency: baseCurrency,
  today: today ?? _today,
);

void main() {
  group('monthlyFactor', () {
    test('brings every cadence to a per-month multiplier', () {
      expect(monthlyFactor(Schedule.daily), 30.44);
      expect(monthlyFactor(Schedule.weekly), 4.35);
      expect(monthlyFactor(Schedule.biweekly), 2.17);
      expect(monthlyFactor(Schedule.monthly), 1);
      expect(monthlyFactor(Schedule.yearly), closeTo(1 / 12, 1e-12));
      // A one-off has no cadence: see `monthlyTotal`.
      expect(monthlyFactor(Schedule.once), 0);
    });
  });

  group('monthlyTotal — schedules', () {
    test('a monthly expense counts once, with its sign', () {
      expect(_total([_op(amount: 100000)]).amountMinor, -100000);
    });

    test('a daily expense counts 30.44 times', () {
      expect(
        _total([_op(amount: 10000, schedule: Schedule.daily)]).amountMinor,
        (-10000 * 30.44).round(),
      );
    });

    test('a biweekly expense counts 2.17 times', () {
      expect(
        _total([_op(amount: 100000, schedule: Schedule.biweekly)]).amountMinor,
        (-100000 * 2.17).round(),
      );
    });

    test('a yearly expense is spread over twelve months', () {
      expect(
        _total([_op(amount: 1200000, schedule: Schedule.yearly)]).amountMinor,
        -100000,
      );
    });

    test('income and expense cancel out', () {
      final total = _total([
        _op(amount: 20000000, kind: OpKind.income),
        _op(amount: 1500000),
      ]);

      expect(total.amountMinor, 20000000 - 1500000);
      expect(total.partial, isFalse);
    });
  });

  group('monthlyTotal — one-off operations', () {
    test('counts in full inside the current month', () {
      final total = _total([
        _op(amount: 450000, schedule: Schedule.once, startDate: _today),
      ]);

      expect(total.amountMinor, -450000);
    });

    test('is left out when its date is in another month', () {
      final past = _total([
        _op(
          amount: 450000,
          schedule: Schedule.once,
          startDate: DateTime(2026, 2, 10),
        ),
      ]);
      final future = _total([
        _op(
          amount: 450000,
          schedule: Schedule.once,
          startDate: DateTime(2026, 4, 10),
        ),
      ]);

      expect(past.amountMinor, 0);
      expect(future.amountMinor, 0);
    });

    test('counts on the last day of the month', () {
      final total = _total([
        _op(
          amount: 450000,
          schedule: Schedule.once,
          startDate: DateTime(2026, 3, 31),
        ),
      ]);

      expect(total.amountMinor, -450000);
    });
  });

  group('monthlyTotal — what it leaves out', () {
    test('a disabled operation does not count', () {
      final total = _total([_op(amount: 100000, enabled: false)]);

      expect(total.amountMinor, 0);
      // Not a conversion problem: nothing to warn about.
      expect(total.partial, isFalse);
    });

    test('a series that has not started yet does not count', () {
      final total = _total([
        _op(amount: 100000, startDate: DateTime(2026, 5, 1)),
      ]);

      expect(total.amountMinor, 0);
    });

    test('a series whose end date has passed does not count', () {
      final total = _total([
        _op(
          amount: 100000,
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2026, 2, 28),
        ),
      ]);

      expect(total.amountMinor, 0);
    });

    test('a series ending later this month still counts', () {
      final total = _total([
        _op(
          amount: 100000,
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2026, 3, 20),
        ),
      ]);

      expect(total.amountMinor, -100000);
    });
  });

  group('monthlyTotal — currencies', () {
    test('converts into the base currency', () {
      final total = _total(
        [_op(amount: 10000, code: 'EUR')],
        rates: [_rate('RUB', 90), _rate('EUR', 0.9)],
      );

      // 100 € ÷ 0.9 × 90 = 10 000 ₽, once a month.
      expect(total.amountMinor, -1000000);
      expect(total.partial, isFalse);
    });

    test('reports a missing rate instead of counting the amount as zero', () {
      final total = _total(
        [_op(amount: 100000), _op(amount: 10000, code: 'EUR')],
        rates: [_rate('RUB', 90)],
      );

      // The convertible part is still summed, and the gap is flagged.
      expect(total.amountMinor, -100000);
      expect(total.partial, isTrue);
    });
  });
}
