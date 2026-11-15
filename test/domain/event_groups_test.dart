import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/projection/event_groups.dart';
import 'package:beaver_v2/domain/projection/occurrences.dart';
import 'package:beaver_v2/domain/projection/project_balance.dart';
import 'package:beaver_v2/domain/projection/rate_table.dart';
import 'package:flutter_test/flutter_test.dart';

PlannedOp _op({
  required String id,
  required String title,
  int amount = 5000,
  String code = 'RUB',
  OpKind kind = OpKind.expense,
}) => PlannedOp(
  id: id,
  userId: 'u1',
  title: title,
  amount: amount,
  currencyCode: code,
  kind: kind,
  schedule: Schedule.daily,
  startDate: DateTime(2026, 11, 14),
);

ProjectionEvent _event(PlannedOp op, DateTime date, {int? baseAmountMinor}) =>
    ProjectionEvent(
      date: date,
      op: op,
      amountMinor: op.signedAmount,
      baseAmountMinor: baseAmountMinor ?? op.signedAmount,
    );

/// `count` daily occurrences of [op] starting on [from].
List<ProjectionEvent> _run(
  PlannedOp op,
  DateTime from,
  int count, {
  int? baseAmountMinor,
}) => [
  for (var i = 0; i < count; i++)
    _event(op, addDays(from, i), baseAmountMinor: baseAmountMinor),
];

void main() {
  final food = _op(id: 'o1', title: 'Еда');

  group('groupConsecutiveEvents', () {
    test('an empty list groups into nothing', () {
      expect(groupConsecutiveEvents(const []), isEmpty);
    });

    test('a run of consecutive days collapses into one group', () {
      final groups = groupConsecutiveEvents(
        _run(food, DateTime(2026, 11, 14), 7),
      );

      expect(groups, hasLength(1));
      final group = groups.single;
      expect(group.op, same(food));
      expect(group.firstDate, DateTime(2026, 11, 14));
      expect(group.lastDate, DateTime(2026, 11, 20));
      expect(group.count, 7);
      // The stored amounts are per occurrence; the totals are derived.
      expect(group.amountMinor, -5000);
      expect(group.baseAmountMinor, -5000);
      expect(group.totalAmountMinor, -35000);
      expect(group.totalBaseAmountMinor, -35000);
    });

    test('a single occurrence stays a one-day group', () {
      final groups = groupConsecutiveEvents([
        _event(food, DateTime(2026, 11, 14)),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.count, 1);
      expect(groups.single.firstDate, DateTime(2026, 11, 14));
      expect(groups.single.lastDate, DateTime(2026, 11, 14));
      expect(groups.single.totalAmountMinor, -5000);
    });

    test('a gap of a day splits a run in two', () {
      final groups = groupConsecutiveEvents([
        ..._run(food, DateTime(2026, 11, 14), 3),
        // 17 ноября is skipped.
        ..._run(food, DateTime(2026, 11, 18), 2),
      ]);

      expect(groups, hasLength(2));
      expect(groups[0].firstDate, DateTime(2026, 11, 14));
      expect(groups[0].lastDate, DateTime(2026, 11, 16));
      expect(groups[0].count, 3);
      expect(groups[1].firstDate, DateTime(2026, 11, 18));
      expect(groups[1].lastDate, DateTime(2026, 11, 19));
      expect(groups[1].count, 2);
    });

    test('a weekly cadence never collapses', () {
      final rent = _op(id: 'o2', title: 'Аренда');
      final groups = groupConsecutiveEvents([
        for (var i = 0; i < 4; i++)
          _event(rent, addDays(DateTime(2026, 11, 14), i * 7)),
      ]);

      expect(groups, hasLength(4));
      expect(groups.every((group) => group.count == 1), isTrue);
    });

    test('another operation inside the range keeps its own row and does not '
        'break the run', () {
      final rent = _op(id: 'o2', title: 'Аренда', amount: 300000);
      final events = <ProjectionEvent>[
        ..._run(food, DateTime(2026, 11, 14), 5),
        _event(rent, DateTime(2026, 11, 16)),
      ];
      // `projectBalance` hands the events over sorted by date, then title.
      events.sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.op.title.compareTo(b.op.title);
      });

      final groups = groupConsecutiveEvents(events);

      expect(groups, hasLength(2));
      // The group sits at its first date, so «Еда» still comes first.
      expect(groups[0].op.id, 'o1');
      expect(groups[0].count, 5);
      expect(groups[0].firstDate, DateTime(2026, 11, 14));
      expect(groups[0].lastDate, DateTime(2026, 11, 18));
      expect(groups[1].op.id, 'o2');
      expect(groups[1].count, 1);
    });

    test('two different operations on the same days never merge', () {
      final coffee = _op(id: 'o2', title: 'Кофе', amount: 20000);
      final events = <ProjectionEvent>[
        for (var i = 0; i < 3; i++) ...[
          _event(coffee, addDays(DateTime(2026, 11, 14), i)),
          _event(food, addDays(DateTime(2026, 11, 14), i)),
        ],
      ];

      final groups = groupConsecutiveEvents(events);

      expect(groups, hasLength(2));
      expect(groups.map((group) => group.op.id), ['o2', 'o1']);
      expect(groups.map((group) => group.count), [3, 3]);
    });

    test('an income run keeps its positive sign', () {
      final salary = _op(
        id: 'o3',
        title: 'Зарплата',
        amount: 100000,
        kind: OpKind.income,
      );

      final groups = groupConsecutiveEvents(
        _run(salary, DateTime(2026, 11, 14), 3),
      );

      expect(groups.single.amountMinor, 100000);
      expect(groups.single.totalAmountMinor, 300000);
    });

    test('a missing rate gives a group with no base equivalent', () {
      final hotel = _op(id: 'o4', title: 'Отель', amount: 20000, code: 'EUR');
      final groups = groupConsecutiveEvents([
        for (var i = 0; i < 4; i++)
          ProjectionEvent(
            date: addDays(DateTime(2026, 11, 14), i),
            op: hotel,
            amountMinor: hotel.signedAmount,
            baseAmountMinor: null,
          ),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.count, 4);
      expect(groups.single.baseAmountMinor, isNull);
      expect(groups.single.totalBaseAmountMinor, isNull);
      expect(groups.single.totalAmountMinor, -80000);
    });

    test('a run across a month boundary stays one group', () {
      final groups = groupConsecutiveEvents(
        _run(food, DateTime(2026, 11, 29), 5),
      );

      expect(groups, hasLength(1));
      expect(groups.single.firstDate, DateTime(2026, 11, 29));
      expect(groups.single.lastDate, DateTime(2026, 12, 3));
      expect(groups.single.count, 5);
    });

    test('a run through a DST transition still counts calendar days', () {
      // Group boundaries go through `daysBetween`, which is calendar-based: a
      // 23-hour day must not look like a gap.
      final groups = groupConsecutiveEvents(
        _run(food, DateTime(2026, 3, 27), 6),
      );

      expect(groups, hasLength(1));
      expect(groups.single.count, 6);
      expect(groups.single.lastDate, DateTime(2026, 4, 1));
    });

    test('a group order follows the first date of each run', () {
      final coffee = _op(id: 'o2', title: 'Кофе', amount: 20000);
      final groups = groupConsecutiveEvents([
        ..._run(food, DateTime(2026, 11, 14), 2),
        ..._run(coffee, DateTime(2026, 11, 20), 2),
        ..._run(food, DateTime(2026, 11, 25), 2),
      ]);

      expect(groups.map((group) => group.op.id), ['o1', 'o2', 'o1']);
      expect(groups.map((group) => group.firstDate), [
        DateTime(2026, 11, 14),
        DateTime(2026, 11, 20),
        DateTime(2026, 11, 25),
      ]);
    });

    test('a run of the same op at a changed amount starts a new group', () {
      // Two occurrences that are not interchangeable must not be folded into
      // one «N × amount» row that misstates the total.
      final groups = groupConsecutiveEvents([
        _event(food, DateTime(2026, 11, 14)),
        ProjectionEvent(
          date: DateTime(2026, 11, 15),
          op: food,
          amountMinor: -9000,
          baseAmountMinor: -9000,
        ),
      ]);

      expect(groups, hasLength(2));
      expect(groups[0].amountMinor, -5000);
      expect(groups[1].amountMinor, -9000);
    });
  });

  group('against projectBalance', () {
    test('a daily operation over a window becomes a single group', () {
      final projection = projectBalance(
        accounts: const [],
        ops: [
          PlannedOp(
            id: 'o1',
            userId: 'u1',
            title: 'Еда',
            amount: 5000,
            currencyCode: 'RUB',
            kind: OpKind.expense,
            schedule: Schedule.daily,
            startDate: DateTime(2026, 11, 14),
          ),
        ],
        from: DateTime(2026, 11, 14),
        to: DateTime(2026, 11, 20),
        rates: RateTable.fromRates([
          Rate(
            userId: 'u1',
            code: 'RUB',
            ratePerUsd: 90,
            source: RateSource.auto,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ]),
        baseCurrency: 'RUB',
      );

      expect(projection.events, hasLength(7));
      final groups = groupConsecutiveEvents(projection.events);
      expect(groups, hasLength(1));
      expect(groups.single.count, 7);
      // The run's total matches what the projection actually applied.
      expect(groups.single.totalBaseAmountMinor, projection.endBalance);
    });
  });
}
