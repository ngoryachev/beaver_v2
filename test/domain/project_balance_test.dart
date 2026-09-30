import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/money.dart';
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

    test('names the base currency when it is the unrated one', () {
      // Only EUR has a rate, and the total is asked for in RUB. The conversion
      // fails on the RUB side, so blaming EUR would send the user to the wrong
      // row in settings.
      final eurOnly = RateTable.fromRates([_rate('EUR', 0.9)]);

      final result = projectBalance(
        accounts: [_account(id: 'a1', currencyCode: 'EUR', balance: 10000)],
        ops: const [],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 2),
        rates: eurOnly,
        baseCurrency: 'RUB',
      );

      expect(result.missingRateCodes, {'RUB'});
      expect(result.startBalance, 0);
    });

    test('names both sides when neither has a rate', () {
      final result = projectBalance(
        accounts: [_account(id: 'a1', currencyCode: 'KZT', balance: 10000)],
        ops: const [],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 2),
        rates: RateTable.fromRates(const []),
        baseCurrency: 'RUB',
      );

      expect(result.missingRateCodes, {'KZT', 'RUB'});
    });

    test('an operation reports the base currency too', () {
      final eurOnly = RateTable.fromRates([_rate('EUR', 0.9)]);

      final result = projectBalance(
        accounts: const [],
        ops: [_op(currencyCode: 'EUR', amount: 1000)],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 3),
        rates: eurOnly,
        baseCurrency: 'RUB',
      );

      expect(result.missingRateCodes, {'RUB'});
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

  // The total must never quietly shed money. `convertMinor` returns null both
  // for a rate it lacks and for a product too large to represent, and the second
  // case used to leave both warning sets empty — so the amount vanished from
  // the total with nothing on screen to say so.
  group('nothing leaves the total unrecorded', () {
    // 10 000 000 000 000,00 $ is inside `Money.maxMinor`, so the app accepts and
    // stores it, but converting it at 90 ₽/$ overruns what an amount may hold.
    final hugeButAccepted = Money.tryParse('10000000000000,00')!.minor;
    final rates = RateTable.fromRates([_rate('RUB', 90), _rate('USD', 1)]);

    test('an unconvertible balance is named instead of dropped', () {
      final result = projectBalance(
        accounts: [
          _account(id: 'a1', currencyCode: 'USD', balance: hugeButAccepted),
        ],
        ops: const [],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 2),
        rates: rates,
        baseCurrency: 'RUB',
      );

      expect(result.startBalance, 0, reason: 'it cannot be counted');
      // Reported as unconvertible, not as unrated: USD has a rate here, and
      // «Без курса» would send the user to fix something that is not broken.
      expect(result.unconvertibleCodes, contains('USD'));
      expect(result.missingRateCodes, isEmpty);
    });

    test('an unconvertible operation is named instead of dropped', () {
      final result = projectBalance(
        accounts: [_account(id: 'a1', currencyCode: 'RUB', balance: 100000)],
        ops: [_op(currencyCode: 'USD', amount: hugeButAccepted)],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 5),
        rates: rates,
        baseCurrency: 'RUB',
      );

      expect(result.endBalance, result.startBalance);
      expect(result.unconvertibleCodes, contains('USD'));
      expect(result.missingRateCodes, isEmpty);
    });

    test('an absent rate and an oversized amount are reported apart', () {
      // Both leave the amount out of the total, but only one is fixed by
      // setting a rate — so «Без курса» must not be shown for the other.
      final result = projectBalance(
        accounts: [
          // No rate at all for KZT.
          _account(id: 'a1', currencyCode: 'KZT', balance: 500000),
          // USD has a rate; the amount is simply past what can be expressed.
          _account(
            id: 'a2',
            currencyCode: 'USD',
            balance: hugeButAccepted,
            sortOrder: 1,
          ),
        ],
        ops: const [],
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 2),
        rates: rates,
        baseCurrency: 'RUB',
      );

      expect(result.missingRateCodes, {'KZT'});
      expect(result.unconvertibleCodes, {'USD'});
    });

    test(
      'every live account either counts or is named, whatever the rates',
      () {
        // The invariant behind both cases above, over a spread of balances and
        // rates: an account is in the total, or it is in the warning.
        for (final balance in [0, 100000, 1 << 40, Money.maxMinor ~/ 2]) {
          for (final usdRate in [1.0, 1e-6, 1e6]) {
            final table = RateTable.fromRates([
              _rate('RUB', 90),
              _rate('USD', usdRate),
            ]);
            final result = projectBalance(
              accounts: [
                _account(id: 'a1', currencyCode: 'RUB', balance: 100000),
                _account(id: 'a2', currencyCode: 'USD', balance: balance),
              ],
              ops: const [],
              from: DateTime(2026, 3, 1),
              to: DateTime(2026, 3, 2),
              rates: table,
              baseCurrency: 'RUB',
            );

            final counted =
                result.startBalance != 100000 ||
                table.convertMinor(balance, from: 'USD', to: 'RUB') == 0;
            expect(
              counted ||
                  result.missingRateCodes.contains('USD') ||
                  result.unconvertibleCodes.contains('USD'),
              isTrue,
              reason: 'balance $balance at $usdRate/USD was silently dropped',
            );
          }
        }
      },
    );
  });
}
