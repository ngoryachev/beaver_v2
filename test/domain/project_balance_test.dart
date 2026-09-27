import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/models/scenario.dart';
import 'package:beaver_v2/domain/projection/project_balance.dart';
import 'package:beaver_v2/domain/projection/rate_table.dart';
import 'package:flutter_test/flutter_test.dart';

Account _account({
  String id = 'a1',
  String name = 'Карта',
  String currencyCode = 'RUB',
  int balance = 0,
  bool archived = false,
  int sortOrder = 0,
}) => Account(
  id: id,
  userId: 'u1',
  name: name,
  currencyCode: currencyCode,
  balance: balance,
  archived: archived,
  sortOrder: sortOrder,
);

PlannedOp _op({
  String id = 'op1',
  String title = 'Операция',
  int amount = 10000,
  String currencyCode = 'RUB',
  OpKind kind = OpKind.expense,
  Schedule schedule = Schedule.daily,
  DateTime? startDate,
  DateTime? endDate,
  bool enabled = true,
}) => PlannedOp(
  id: id,
  userId: 'u1',
  title: title,
  amount: amount,
  currencyCode: currencyCode,
  kind: kind,
  schedule: schedule,
  startDate: startDate ?? DateTime(2026, 3, 1),
  endDate: endDate,
  enabled: enabled,
);

Rate _rate(String code, double perUsd, {RateSource source = RateSource.auto}) =>
    Rate(
      userId: 'u1',
      code: code,
      ratePerUsd: perUsd,
      source: source,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

final _rubOnly = RateTable.fromRates([_rate('RUB', 90)]);

void main() {
  group('projectBalance — the headline case', () {
    test('1000 ₽ minus 100 ₽ a day for 10 days lands exactly on 0', () {
      // Day 1 already spends 100, so the window must be 10 days long: 01.03–10.03.
      final result = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: [_op(amount: 10000, startDate: DateTime(2026, 3, 1))],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 10),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.startBalance, 100000);
      expect(result.endBalance, 0);
      expect(result.points, hasLength(10));
      expect(result.points.last.balanceMinor, 0);
      expect(result.events, hasLength(10));
      expect(result.minBalance, 0);
      expect(result.minDate, DateTime(2026, 3, 10));
      expect(result.missingRateCodes, isEmpty);
    });

    test('the balance walks down one step per day', () {
      final result = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: [_op(amount: 10000)],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 10),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.points.map((p) => p.balanceMinor).toList(), [
        90000,
        80000,
        70000,
        60000,
        50000,
        40000,
        30000,
        20000,
        10000,
        0,
      ]);
    });
  });

  group('projectBalance — operations never touch the stored balance', () {
    test('the account object is left untouched', () {
      final account = _account(balance: 100000);

      projectBalance(
        accounts: [account],
        ops: [_op(amount: 10000)],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(account.balance, 100000);
    });

    test('income raises and expense lowers the end balance', () {
      final income = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: [_op(amount: 50000, kind: OpKind.income, schedule: Schedule.once)],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );
      final expense = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: [
          _op(amount: 50000, kind: OpKind.expense, schedule: Schedule.once),
        ],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(income.endBalance, 150000);
      expect(expense.endBalance, 50000);
    });
  });

  group('projectBalance — enabled flag', () {
    test('a disabled operation changes nothing', () {
      final result = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: [_op(amount: 10000, enabled: false)],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 10),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.startBalance, 100000);
      expect(result.endBalance, 100000);
      expect(result.events, isEmpty);
      expect(result.minBalance, 100000);
    });

    test('a disabled operation does not report its currency as missing', () {
      final result = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: [_op(currencyCode: 'KZT', enabled: false)],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 10),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.missingRateCodes, isEmpty);
    });
  });

  group('projectBalance — once', () {
    test('fires exactly once inside the window', () {
      final result = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: [
          _op(
            amount: 25000,
            schedule: Schedule.once,
            startDate: DateTime(2026, 3, 15),
          ),
        ],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.events, hasLength(1));
      expect(result.events.single.date, DateTime(2026, 3, 15));
      expect(result.endBalance, 75000);
    });

    test('does not fire when its date lies outside the window', () {
      final result = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: [
          _op(
            amount: 25000,
            schedule: Schedule.once,
            startDate: DateTime(2026, 4, 15),
          ),
        ],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.events, isEmpty);
      expect(result.endBalance, 100000);
    });
  });

  group('projectBalance — end_date', () {
    test('truncates a daily series so the balance stops falling', () {
      final result = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: [
          _op(
            amount: 10000,
            startDate: DateTime(2026, 3, 1),
            endDate: DateTime(2026, 3, 3),
          ),
        ],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 10),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.events, hasLength(3));
      expect(result.endBalance, 70000);
      expect(result.minBalance, 70000);
      expect(result.minDate, DateTime(2026, 3, 3));
    });
  });

  group('projectBalance — scenarios', () {
    test('an account excluded by the scenario is left out of startBalance', () {
      final accounts = [
        _account(id: 'a1', name: 'Карта', balance: 100000),
        _account(id: 'a2', name: 'Наличные', balance: 50000),
      ];
      final scenario = Scenario(
        id: 's2',
        userId: 'u1',
        name: 'Без наличных',
        disabledAccountIds: const {'a2'},
      );

      final result = projectBalance(
        accounts: accounts.where((a) => scenario.allowsAccount(a.id)).toList(),
        ops: const [],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 10),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.startBalance, 100000);
      expect(result.endBalance, 100000);
    });

    test('an operation excluded by the scenario does not fire', () {
      final ops = [
        _op(id: 'op1', amount: 10000),
        _op(id: 'op2', amount: 20000),
      ];
      final scenario = Scenario(
        id: 's2',
        userId: 'u1',
        name: 'Без второй',
        disabledOpIds: const {'op2'},
      );

      final result = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: ops.where((o) => scenario.allowsOp(o.id)).toList(),
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 2),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.events, hasLength(2));
      expect(result.endBalance, 80000);
    });

    test('the default scenario excludes nothing', () {
      final scenario = Scenario(
        id: 's1',
        userId: 'u1',
        name: 'Все',
        isDefault: true,
      );

      expect(scenario.allowsAccount('anything'), isTrue);
      expect(scenario.allowsOp('anything'), isTrue);
    });
  });

  group('projectBalance — archived accounts', () {
    test('are excluded from startBalance', () {
      final result = projectBalance(
        accounts: [
          _account(id: 'a1', balance: 100000),
          _account(id: 'a2', balance: 50000, archived: true),
        ],
        ops: const [],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 2),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.startBalance, 100000);
    });
  });

  group('projectBalance — missing rates', () {
    test('an account currency without a rate is reported, not counted as 0', () {
      final result = projectBalance(
        accounts: [
          _account(id: 'a1', balance: 100000),
          _account(id: 'a2', currencyCode: 'KZT', balance: 500000),
        ],
        ops: const [],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 2),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.missingRateCodes, {'KZT'});
      // The KZT balance is omitted rather than folded in as zero, so the total
      // stays honest and the UI can say "some currencies have no rate".
      expect(result.startBalance, 100000);
    });

    test('an operation currency without a rate is reported and skipped', () {
      final result = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: [_op(currencyCode: 'GEL', amount: 1000)],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 10),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.missingRateCodes, {'GEL'});
      expect(result.endBalance, 100000);
      // The events are still listed, with a null base amount to flag them.
      expect(result.events, hasLength(10));
      expect(result.events.first.baseAmountMinor, isNull);
      expect(result.events.first.amountMinor, -1000);
    });

    test('a rate added later removes the code from missingRateCodes', () {
      final withRate = RateTable.fromRates([
        _rate('RUB', 90),
        _rate('KZT', 500),
      ]);

      final result = projectBalance(
        accounts: [
          _account(id: 'a1', balance: 100000),
          _account(id: 'a2', currencyCode: 'KZT', balance: 500000),
        ],
        ops: const [],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 2),
        rates: withRate,
        baseCurrency: 'RUB',
      );

      expect(result.missingRateCodes, isEmpty);
      // 5000.00 KZT ÷ 500 × 90 = 900.00 RUB on top of 1000.00 RUB.
      expect(result.startBalance, 190000);
    });
  });

  group('projectBalance — multi-currency totals', () {
    test('sums accounts through the base currency', () {
      final rates = RateTable.fromRates([_rate('RUB', 90), _rate('EUR', 0.9)]);

      final result = projectBalance(
        accounts: [
          _account(id: 'a1', currencyCode: 'RUB', balance: 90000),
          _account(id: 'a2', currencyCode: 'EUR', balance: 10000),
        ],
        ops: const [],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 2),
        rates: rates,
        baseCurrency: 'EUR',
      );

      // 900 RUB → 9 EUR, plus 100 EUR.
      expect(result.startBalance, 10900);
    });

    test('a manual rate changes the total', () {
      final auto = RateTable.fromRates([_rate('RUB', 90)]);
      final manual = RateTable.fromRates([
        _rate('RUB', 90),
        _rate('RUB', 100, source: RateSource.manual),
      ]);
      final account = _account(currencyCode: 'RUB', balance: 90000);

      int total(RateTable table) => projectBalance(
        accounts: [account],
        ops: const [],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 2),
        rates: table,
        baseCurrency: 'USD',
      ).startBalance;

      expect(total(auto), 1000);
      expect(total(manual), 900);
    });
  });

  group('projectBalance — minimum tracking', () {
    test('finds a dip in the middle of the window', () {
      final result = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: [
          _op(
            id: 'op1',
            title: 'Трата',
            amount: 80000,
            schedule: Schedule.once,
            startDate: DateTime(2026, 3, 5),
          ),
          _op(
            id: 'op2',
            title: 'Зарплата',
            amount: 200000,
            kind: OpKind.income,
            schedule: Schedule.once,
            startDate: DateTime(2026, 3, 20),
          ),
        ],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.minBalance, 20000);
      expect(result.minDate, DateTime(2026, 3, 5));
      expect(result.endBalance, 220000);
    });

    test('with no events the minimum is the starting balance on day one', () {
      final result = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: const [],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.minBalance, 100000);
      expect(result.minDate, DateTime(2026, 3, 1));
      expect(result.points, hasLength(31));
    });

    test('tracks a balance going negative', () {
      final result = projectBalance(
        accounts: [_account(balance: 10000)],
        ops: [_op(amount: 10000)],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 5),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.endBalance, -40000);
      expect(result.minBalance, -40000);
      expect(result.minDate, DateTime(2026, 3, 5));
    });
  });

  group('projectBalance — events', () {
    test('are sorted chronologically', () {
      final result = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: [
          _op(
            id: 'op1',
            title: 'Позже',
            schedule: Schedule.once,
            startDate: DateTime(2026, 3, 20),
          ),
          _op(
            id: 'op2',
            title: 'Раньше',
            schedule: Schedule.once,
            startDate: DateTime(2026, 3, 5),
          ),
        ],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.events.map((e) => e.op.title).toList(), [
        'Раньше',
        'Позже',
      ]);
    });

    test('an inverted window collapses to a single day', () {
      final result = projectBalance(
        accounts: [_account(balance: 100000)],
        ops: const [],
        from: DateTime(2026, 3, 10),
        to: DateTime(2026, 3, 1),
        rates: _rubOnly,
        baseCurrency: 'RUB',
      );

      expect(result.points, hasLength(1));
      expect(result.endBalance, 100000);
    });
  });

  group('base currency invariant', () {
    test(
      'candidates are the non-archived account currencies, deduplicated',
      () {
        final accounts = [
          _account(id: 'a1', currencyCode: 'RUB'),
          _account(id: 'a2', currencyCode: 'EUR', sortOrder: 1),
          _account(id: 'a3', currencyCode: 'RUB', sortOrder: 2),
          _account(id: 'a4', currencyCode: 'KZT', archived: true, sortOrder: 3),
        ];

        expect(baseCurrencyCandidates(accounts), ['RUB', 'EUR']);
      },
    );

    test('a base currency outside the candidate set is replaced', () {
      final accounts = [_account(currencyCode: 'EUR')];

      expect(normalizeBaseCurrency('KZT', accounts), 'EUR');
    });

    test('a valid base currency is kept', () {
      final accounts = [
        _account(id: 'a1', currencyCode: 'EUR'),
        _account(id: 'a2', currencyCode: 'RUB', sortOrder: 1),
      ];

      expect(normalizeBaseCurrency('RUB', accounts), 'RUB');
    });

    test(
      'archiving the last account of a currency moves the base currency',
      () {
        final accounts = [
          _account(id: 'a1', currencyCode: 'EUR', archived: true),
          _account(id: 'a2', currencyCode: 'RUB', sortOrder: 1),
        ];

        expect(normalizeBaseCurrency('EUR', accounts), 'RUB');
      },
    );

    test('with no accounts the stored base currency survives', () {
      expect(normalizeBaseCurrency('KZT', const []), 'KZT');
    });
  });
}
