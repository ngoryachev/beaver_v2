import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/projection/event_groups.dart';
import 'package:beaver_v2/domain/projection/occurrences.dart';
import 'package:beaver_v2/domain/projection/project_balance.dart';
import 'package:flutter_test/flutter_test.dart';

/// Folding the event list is only safe if nothing is lost or invented on the
/// way: the row the user reads replaces N rows, so «N × amount» has to add up
/// to exactly what the projection applied, and the dates it names have to be
/// the dates the occurrences fell on.
///
/// These checks are the invariants behind that claim, plus the shapes
/// `groupConsecutiveEvents` meets on real schedules rather than on a
/// hand-written list.
PlannedOp _op({
  required String id,
  required String title,
  int amount = 5000,
  String code = 'RUB',
  OpKind kind = OpKind.expense,
  Schedule schedule = Schedule.daily,
  DateTime? startDate,
  DateTime? endDate,
}) => PlannedOp(
  id: id,
  userId: 'u1',
  title: title,
  amount: amount,
  currencyCode: code,
  kind: kind,
  schedule: schedule,
  startDate: startDate ?? DateTime(2026, 11, 14),
  endDate: endDate,
);

ProjectionEvent _event(PlannedOp op, DateTime date, {int? baseAmountMinor}) =>
    ProjectionEvent(
      date: date,
      op: op,
      amountMinor: op.signedAmount,
      baseAmountMinor: baseAmountMinor ?? op.signedAmount,
    );

/// Every occurrence [op] has inside `[from, to]`, as `projectBalance` builds
/// them — same order, same amounts.
List<ProjectionEvent> _eventsOf(
  List<PlannedOp> ops,
  DateTime from,
  DateTime to,
) {
  final events = <ProjectionEvent>[
    for (final op in ops)
      for (final date in occurrencesBetween(op, from, to)) _event(op, date),
  ];
  events.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.op.title.compareTo(b.op.title);
  });
  return events;
}

void main() {
  group('grouping loses nothing', () {
    test('the occurrences and the money add up over a mixed month', () {
      final ops = [
        _op(id: 'o1', title: 'Еда'),
        _op(
          id: 'o2',
          title: 'Кофе',
          amount: 20000,
          schedule: Schedule.weekly,
          startDate: DateTime(2026, 11, 16),
        ),
        _op(
          id: 'o3',
          title: 'Аренда',
          amount: 3000000,
          schedule: Schedule.monthly,
          startDate: DateTime(2026, 11, 20),
        ),
        _op(
          id: 'o4',
          title: 'Зарплата',
          amount: 10000000,
          kind: OpKind.income,
          schedule: Schedule.monthly,
          startDate: DateTime(2026, 11, 25),
        ),
      ];
      final events = _eventsOf(ops, DateTime(2026, 11, 14), DateTime(2027, 2, 1));
      final groups = groupConsecutiveEvents(events);

      expect(
        groups.fold<int>(0, (sum, group) => sum + group.count),
        events.length,
        reason: 'every occurrence has to end up in exactly one group',
      );
      expect(
        groups.fold<int>(0, (sum, group) => sum + group.totalAmountMinor),
        events.fold<int>(0, (sum, event) => sum + event.amountMinor),
        reason: 'the collapsed totals must sum to what the projection applied',
      );
      expect(
        groups.fold<int>(0, (sum, group) => sum + group.totalBaseAmountMinor!),
        events.fold<int>(0, (sum, event) => sum + event.baseAmountMinor!),
      );
    });

    test('a group names exactly the days it covers', () {
      final events = _eventsOf(
        [
          _op(id: 'o1', title: 'Еда'),
          _op(
            id: 'o2',
            title: 'Кофе',
            amount: 20000,
            schedule: Schedule.biweekly,
            startDate: DateTime(2026, 11, 18),
          ),
        ],
        DateTime(2026, 11, 14),
        DateTime(2027, 1, 31),
      );

      for (final group in groupConsecutiveEvents(events)) {
        expect(
          daysBetween(group.firstDate, group.lastDate) + 1,
          group.count,
          reason:
              '«${group.count} дн.» must match the range '
              '${group.firstDate} – ${group.lastDate}',
        );
        expect(group.lastDate.isBefore(group.firstDate), isFalse);
        expect(group.firstDate, dateOnly(group.firstDate));
        expect(group.lastDate, dateOnly(group.lastDate));
      }
    });

    test('the groups come out ordered by their first date', () {
      final groups = groupConsecutiveEvents(
        _eventsOf(
          [
            _op(
              id: 'o1',
              title: 'Еда',
              endDate: DateTime(2026, 11, 20),
            ),
            // Starts again after a gap: its second run must not be hoisted
            // next to the first.
            _op(
              id: 'o2',
              title: 'Еда',
              startDate: DateTime(2026, 11, 25),
              endDate: DateTime(2026, 11, 28),
            ),
            _op(
              id: 'o3',
              title: 'Налог',
              amount: 100000,
              schedule: Schedule.once,
              startDate: DateTime(2026, 11, 22),
            ),
          ],
          DateTime(2026, 11, 14),
          DateTime(2026, 11, 30),
        ),
      );

      expect(groups.map((group) => group.op.id), ['o1', 'o3', 'o2']);
      for (var i = 1; i < groups.length; i++) {
        expect(
          groups[i].firstDate.isBefore(groups[i - 1].firstDate),
          isFalse,
          reason: 'group $i jumped ahead of its predecessor',
        );
      }
    });
  });

  group('operations that look alike', () {
    test('same title and amount, different ids, never merge', () {
      // Two separate operations the user happened to name the same: folding
      // them would claim one op fired on both days.
      final first = _op(id: 'o1', title: 'Еда');
      final second = _op(id: 'o2', title: 'Еда');

      final groups = groupConsecutiveEvents([
        _event(first, DateTime(2026, 11, 14)),
        _event(second, DateTime(2026, 11, 15)),
      ]);

      expect(groups, hasLength(2));
      expect(groups.map((group) => group.op.id), ['o1', 'o2']);
      expect(groups.every((group) => group.count == 1), isTrue);
    });

    test('an op firing twice on one day is not folded into a two-day run', () {
      // Not reachable through `occurrencesBetween` today, but the row would
      // lie about the dates if it were: one day must never read as «2 дн.».
      final food = _op(id: 'o1', title: 'Еда');
      final groups = groupConsecutiveEvents([
        _event(food, DateTime(2026, 11, 14)),
        _event(food, DateTime(2026, 11, 14)),
        _event(food, DateTime(2026, 11, 15)),
      ]);

      expect(
        groups.fold<int>(0, (sum, group) => sum + group.count),
        3,
        reason: 'no occurrence may be dropped',
      );
      for (final group in groups) {
        expect(daysBetween(group.firstDate, group.lastDate) + 1, group.count);
      }
    });
  });

  group('real schedules', () {
    test('a monthly operation anchored on the 31st never collapses', () {
      // The clamped dates (31 янв → 28 фев → 31 мар) are the closest a
      // non-daily schedule comes to consecutive days.
      final groups = groupConsecutiveEvents(
        _eventsOf(
          [
            _op(
              id: 'o1',
              title: 'Аренда',
              amount: 3000000,
              schedule: Schedule.monthly,
              startDate: DateTime(2026, 1, 31),
            ),
          ],
          DateTime(2026, 1, 1),
          DateTime(2027, 1, 1),
        ),
      );

      expect(groups, hasLength(12));
      expect(groups.every((group) => group.count == 1), isTrue);
    });

    test('a daily run clipped by end_date stops at the last occurrence', () {
      final groups = groupConsecutiveEvents(
        _eventsOf(
          [
            _op(
              id: 'o1',
              title: 'Еда',
              endDate: DateTime(2026, 11, 18),
            ),
          ],
          DateTime(2026, 11, 14),
          DateTime(2026, 12, 31),
        ),
      );

      expect(groups, hasLength(1));
      expect(groups.single.count, 5);
      expect(groups.single.lastDate, DateTime(2026, 11, 18));
    });

    test('a daily run clipped by the window start begins at the window', () {
      final groups = groupConsecutiveEvents(
        _eventsOf(
          [_op(id: 'o1', title: 'Еда', startDate: DateTime(2026, 1, 1))],
          DateTime(2026, 11, 14),
          DateTime(2026, 11, 17),
        ),
      );

      expect(groups, hasLength(1));
      expect(groups.single.firstDate, DateTime(2026, 11, 14));
      expect(groups.single.count, 4);
    });

    test('a two-day run is still a run', () {
      final groups = groupConsecutiveEvents(
        _eventsOf(
          [_op(id: 'o1', title: 'Еда', endDate: DateTime(2026, 11, 15))],
          DateTime(2026, 11, 14),
          DateTime(2026, 11, 30),
        ),
      );

      expect(groups, hasLength(1));
      expect(groups.single.count, 2);
      expect(groups.single.totalAmountMinor, -10000);
    });
  });
}
