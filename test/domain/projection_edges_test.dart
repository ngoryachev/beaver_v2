import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/projection/occurrences.dart';
import 'package:beaver_v2/domain/projection/project_balance.dart';
import 'package:beaver_v2/domain/projection/rate_table.dart';
import 'package:flutter_test/flutter_test.dart';

/// Edge cases around the month-skipping fast path in [occurrencesBetween] and
/// the invariants [projectBalance] advertises but does not assert itself.
void main() {
  PlannedOp op(
    Schedule schedule,
    DateTime startDate, {
    DateTime? endDate,
    int amount = 10000,
    OpKind kind = OpKind.expense,
    String currencyCode = 'RUB',
    String title = 'Оп',
    bool enabled = true,
  }) => PlannedOp(
    id: title,
    userId: 'u1',
    title: title,
    amount: amount,
    currencyCode: currencyCode,
    kind: kind,
    schedule: schedule,
    startDate: startDate,
    endDate: endDate,
    enabled: enabled,
  );

  Account account(
    int balance, {
    String currencyCode = 'RUB',
    String id = 'a1',
    bool archived = false,
  }) => Account(
    id: id,
    userId: 'u1',
    name: 'Счёт $id',
    currencyCode: currencyCode,
    balance: balance,
    archived: archived,
  );

  Rate rate(String code, double value, {RateSource source = RateSource.auto}) =>
      Rate(
        userId: 'u1',
        code: code,
        ratePerUsd: value,
        source: source,
        updatedAt: DateTime.utc(2026),
      );

  group('occurrencesBetween — the monthly month-skip fast path', () {
    // The fast path jumps `index` straight to the window's month and then walks
    // it back. These windows are the ones where the jump can overshoot or land
    // short, so the day-by-day result must still be exact.

    test('a 31st anchor crossing a year boundary keeps clamping', () {
      final dates = occurrencesBetween(
        op(Schedule.monthly, DateTime(2025, 12, 31)),
        DateTime(2026, 1, 1),
        DateTime(2026, 4, 30),
      );

      expect(dates, [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    });

    test('a window opening after the anchor day skips that month', () {
      // Anchor on the 15th, window opens on the 20th: March is already past.
      final dates = occurrencesBetween(
        op(Schedule.monthly, DateTime(2026, 1, 15)),
        DateTime(2026, 3, 20),
        DateTime(2026, 6, 1),
      );

      expect(dates, [
        DateTime(2026, 4, 15),
        DateTime(2026, 5, 15),
      ]);
    });

    test('a window opening exactly on an occurrence includes it', () {
      final dates = occurrencesBetween(
        op(Schedule.monthly, DateTime(2026, 1, 15)),
        DateTime(2026, 3, 15),
        DateTime(2026, 5, 14),
      );

      expect(dates, [
        DateTime(2026, 3, 15),
        DateTime(2026, 4, 15),
      ]);
    });

    test('a window opening inside February with a 31st anchor', () {
      final dates = occurrencesBetween(
        op(Schedule.monthly, DateTime(2026, 1, 31)),
        DateTime(2026, 2, 10),
        DateTime(2026, 4, 30),
      );

      expect(dates, [
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    });

    test('a window many years after the anchor is not off by a month', () {
      final dates = occurrencesBetween(
        op(Schedule.monthly, DateTime(2020, 3, 5)),
        DateTime(2026, 7, 1),
        DateTime(2026, 9, 30),
      );

      expect(dates, [
        DateTime(2026, 7, 5),
        DateTime(2026, 8, 5),
        DateTime(2026, 9, 5),
      ]);
    });

    test('the fast path agrees with a naive month-by-month walk', () {
      // Every anchor day against every window start, for a year — the fast path
      // must never drop, duplicate or shift an occurrence.
      for (var anchorDay = 28; anchorDay <= 31; anchorDay++) {
        final start = DateTime(2025, 1, anchorDay);
        for (var offset = 0; offset < 365; offset += 17) {
          final from = addDays(DateTime(2025, 1, 1), offset);
          final to = addDays(from, 120);

          final expected = <DateTime>[];
          for (var index = 0; index < 400; index++) {
            final totalMonths = start.month - 1 + index;
            final year = start.year + totalMonths ~/ 12;
            final month = totalMonths % 12 + 1;
            final lastDay = DateTime(year, month + 1, 0).day;
            final date = DateTime(
              year,
              month,
              start.day <= lastDay ? start.day : lastDay,
            );
            if (date.isAfter(to)) break;
            if (!date.isBefore(from)) expected.add(date);
          }

          expect(
            occurrencesBetween(op(Schedule.monthly, start), from, to),
            expected,
            reason: 'anchor $start, window $from..$to',
          );
        }
      }
    });
  });

  group('occurrencesBetween — weekly and yearly edges', () {
    test('a window opening exactly on a weekly occurrence includes it', () {
      final dates = occurrencesBetween(
        op(Schedule.weekly, DateTime(2026, 1, 1)),
        DateTime(2026, 1, 15),
        DateTime(2026, 2, 1),
      );

      expect(dates, [
        DateTime(2026, 1, 15),
        DateTime(2026, 1, 22),
        DateTime(2026, 1, 29),
      ]);
    });

    test('a weekly series is capped by end_date mid-cycle', () {
      final dates = occurrencesBetween(
        op(
          Schedule.weekly,
          DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 20),
        ),
        DateTime(2026, 1, 1),
        DateTime(2026, 3, 1),
      );

      expect(dates, [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 8),
        DateTime(2026, 1, 15),
      ]);
    });

    test('a 29 February anchor returns to the 29th in the next leap year', () {
      final dates = occurrencesBetween(
        op(Schedule.yearly, DateTime(2024, 2, 29)),
        DateTime(2025, 1, 1),
        DateTime(2028, 12, 31),
      );

      expect(dates, [
        DateTime(2025, 2, 28),
        DateTime(2026, 2, 28),
        DateTime(2027, 2, 28),
        DateTime(2028, 2, 29),
      ]);
    });

    test('a daily series whose end_date equals its start fires once', () {
      final dates = occurrencesBetween(
        op(Schedule.daily, DateTime(2026, 5, 5), endDate: DateTime(2026, 5, 5)),
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 31),
      );

      expect(dates, [DateTime(2026, 5, 5)]);
    });
  });

  group('projectBalance — structural invariants', () {
    final rates = RateTable.fromRates([rate('RUB', 100), rate('EUR', 0.9)]);

    test('there is exactly one point per day of the window, inclusive', () {
      final result = projectBalance(
        accounts: [account(100000)],
        ops: const [],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
        rates: rates,
        baseCurrency: 'RUB',
      );

      expect(result.points, hasLength(31));
      expect(result.points.first.date, DateTime(2026, 3, 1));
      expect(result.points.last.date, DateTime(2026, 3, 31));
    });

    test('endBalance equals the last point', () {
      final result = projectBalance(
        accounts: [account(100000)],
        ops: [op(Schedule.daily, DateTime(2026, 3, 1), amount: 1000)],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 10),
        rates: rates,
        baseCurrency: 'RUB',
      );

      expect(result.endBalance, result.points.last.balanceMinor);
      expect(result.minBalance, lessThanOrEqualTo(result.startBalance));
    });

    test('minDate is the first day the minimum is reached, not the last', () {
      // Down 500 on day 2, back up 500 on day 4: the dip is a plateau across
      // days 2 and 3, and the earlier of the two is the one to report.
      final result = projectBalance(
        accounts: [account(100000)],
        ops: [
          op(
            Schedule.once,
            DateTime(2026, 3, 2),
            amount: 50000,
            title: 'Списание',
          ),
          op(
            Schedule.once,
            DateTime(2026, 3, 4),
            amount: 50000,
            kind: OpKind.income,
            title: 'Возврат',
          ),
        ],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 5),
        rates: rates,
        baseCurrency: 'RUB',
      );

      expect(result.minBalance, 50000);
      expect(result.minDate, DateTime(2026, 3, 2));
    });

    test('two operations on the same day both apply', () {
      final result = projectBalance(
        accounts: [account(100000)],
        ops: [
          op(Schedule.once, DateTime(2026, 3, 2), amount: 1000, title: 'A'),
          op(Schedule.once, DateTime(2026, 3, 2), amount: 2000, title: 'B'),
        ],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 3),
        rates: rates,
        baseCurrency: 'RUB',
      );

      expect(result.endBalance, 100000 - 3000);
      expect(result.events, hasLength(2));
    });

    test('a day-granular walk ignores a time-of-day on the window bounds', () {
      final withTime = projectBalance(
        accounts: [account(100000)],
        ops: [op(Schedule.daily, DateTime(2026, 3, 1), amount: 1000)],
        from: DateTime(2026, 3, 1, 23, 59),
        to: DateTime(2026, 3, 5, 0, 1),
        rates: rates,
        baseCurrency: 'RUB',
      );
      final withoutTime = projectBalance(
        accounts: [account(100000)],
        ops: [op(Schedule.daily, DateTime(2026, 3, 1), amount: 1000)],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 5),
        rates: rates,
        baseCurrency: 'RUB',
      );

      expect(withTime.endBalance, withoutTime.endBalance);
      expect(withTime.points.length, withoutTime.points.length);
    });

    test('an archived account in the base currency is still left out', () {
      final result = projectBalance(
        accounts: [account(100000), account(500000, id: 'a2', archived: true)],
        ops: const [],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 2),
        rates: rates,
        baseCurrency: 'RUB',
      );

      expect(result.startBalance, 100000);
    });

    test('an archived account does not drag in a missing-rate warning', () {
      final result = projectBalance(
        accounts: [account(100000), account(500, id: 'a2', currencyCode: 'JPY', archived: true)],
        ops: const [],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 2),
        rates: rates,
        baseCurrency: 'RUB',
      );

      expect(result.missingRateCodes, isEmpty);
    });
  });

  group('RateTable — rounding across differing precision', () {
    test('a 0-decimal currency converts without losing a whole unit', () {
      final table = RateTable.fromRates([rate('JPY', 150), rate('RUB', 90)]);

      // 15000 JPY = 100 USD = 9000 RUB.
      expect(
        table.convertMinor(15000, from: 'JPY', to: 'RUB'),
        900000,
      );
      expect(
        table.convertMinor(900000, from: 'RUB', to: 'JPY'),
        15000,
      );
    });

    test('a cross-rate is symmetric to within one minor unit', () {
      final table = RateTable.fromRates([rate('RUB', 90.5), rate('EUR', 0.93)]);

      final toEur = table.convertMinor(100000, from: 'RUB', to: 'EUR')!;
      final back = table.convertMinor(toEur, from: 'EUR', to: 'RUB')!;

      expect((back - 100000).abs(), lessThanOrEqualTo(100));
    });

    test('a manual rate still wins when the auto row is newer', () {
      final table = RateTable.fromRates([
        Rate(
          userId: 'u1',
          code: 'RUB',
          ratePerUsd: 90,
          source: RateSource.manual,
          updatedAt: DateTime.utc(2020),
        ),
        Rate(
          userId: 'u1',
          code: 'RUB',
          ratePerUsd: 100,
          source: RateSource.auto,
          updatedAt: DateTime.utc(2026),
        ),
      ]);

      expect(table.rateFor('RUB'), 90);
    });
  });

  group('base currency invariant under archiving', () {
    test('archiving the last account of a currency moves the base off it', () {
      final accounts = [
        account(1000, currencyCode: 'EUR', id: 'a1', archived: true),
        account(1000, currencyCode: 'RUB', id: 'a2'),
      ];

      expect(baseCurrencyCandidates(accounts), ['RUB']);
      expect(normalizeBaseCurrency('EUR', accounts), 'RUB');
    });
  });
}
