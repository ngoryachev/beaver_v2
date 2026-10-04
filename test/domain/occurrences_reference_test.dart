import 'dart:math';

import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/projection/occurrences.dart';
import 'package:flutter_test/flutter_test.dart';

/// `occurrencesBetween` skips whole weeks, months and years at a time to avoid
/// walking day by day. That fast path is where an off-by-one hides, so these
/// tests compare it against a deliberately naive reference: ask "does this
/// operation fire today?" for every single day of the window.
///
/// The reference never shifts a cursor, so the two implementations share no
/// arithmetic beyond the calendar helpers themselves.
bool _firesOn(PlannedOp op, DateTime day) {
  final start = dateOnly(op.startDate);
  if (day.isBefore(start)) return false;
  if (op.endDate != null && day.isAfter(dateOnly(op.endDate!))) return false;

  // The day an anchored series lands on in `day`'s own month: the anchor day,
  // pulled back to the month's last day when the month is too short.
  int clampedDay(int year, int month) {
    final length = daysInMonth(year, month);
    return start.day <= length ? start.day : length;
  }

  return switch (op.schedule) {
    Schedule.once => day == start,
    Schedule.daily => true,
    Schedule.weekly => daysBetween(start, day) % 7 == 0,
    Schedule.biweekly => daysBetween(start, day) % 14 == 0,
    Schedule.monthly => day.day == clampedDay(day.year, day.month),
    Schedule.yearly =>
      day.month == start.month && day.day == clampedDay(day.year, day.month),
  };
}

List<DateTime> _reference(PlannedOp op, DateTime from, DateTime to) {
  final result = <DateTime>[];
  final windowFrom = dateOnly(from);
  final windowTo = dateOnly(to);
  for (var day = windowFrom; !day.isAfter(windowTo); day = addDays(day, 1)) {
    if (_firesOn(op, day)) result.add(day);
  }
  return result;
}

PlannedOp _op({
  required Schedule schedule,
  required DateTime startDate,
  DateTime? endDate,
}) => PlannedOp(
  id: 'op1',
  userId: 'u1',
  title: 'Тест',
  amount: 10000,
  currencyCode: 'RUB',
  kind: OpKind.expense,
  schedule: schedule,
  startDate: startDate,
  endDate: endDate,
);

String _label(PlannedOp op, DateTime from, DateTime to) =>
    '${op.schedule.wire} start=${op.startDate.toIso8601String().substring(0, 10)} '
    'end=${op.endDate?.toIso8601String().substring(0, 10) ?? '-'} '
    'window=${from.toIso8601String().substring(0, 10)}..'
    '${to.toIso8601String().substring(0, 10)}';

void main() {
  group('occurrencesBetween matches a day-by-day reference', () {
    // Fixed seed: a failure is reproducible and reportable, unlike a fresh
    // random sample on every run.
    final random = Random(20260927);

    for (final schedule in Schedule.values) {
      test('for ${schedule.wire} over 400 random windows', () {
        for (var i = 0; i < 400; i++) {
          // Month ends and leap days are where the clamping happens, so the
          // start day is drawn from the whole 1..31 range.
          final start = DateTime(
            2024 + random.nextInt(4),
            1 + random.nextInt(12),
            1 + random.nextInt(31),
          );
          // Windows land before, around and after the start date.
          final from = addDays(start, random.nextInt(900) - 450);
          final to = addDays(from, random.nextInt(420));
          final endDate = random.nextBool()
              ? addDays(start, random.nextInt(600))
              : null;
          final op = _op(
            schedule: schedule,
            startDate: start,
            endDate: endDate,
          );

          expect(
            occurrencesBetween(op, from, to),
            _reference(op, from, to),
            reason: _label(op, from, to),
          );
        }
      });
    }
  });

  group('occurrencesBetween output shape', () {
    test('is sorted, unique and inside the window', () {
      final random = Random(1);
      for (var i = 0; i < 300; i++) {
        final schedule =
            Schedule.values[random.nextInt(Schedule.values.length)];
        final start = DateTime(
          2025 + random.nextInt(3),
          1 + random.nextInt(12),
          1 + random.nextInt(31),
        );
        final from = addDays(start, random.nextInt(400) - 200);
        final to = addDays(from, random.nextInt(200));
        final dates = occurrencesBetween(
          _op(schedule: schedule, startDate: start),
          from,
          to,
        );

        for (final date in dates) {
          // Not `date.hour == 0`: where DST springs forward at midnight
          // (America/Santiago, America/Havana, Asia/Tehran) that instant does
          // not exist and Dart normalises `DateTime(y, m, d)` to 01:00. What
          // `projectBalance` actually relies on is that an occurrence is the
          // canonical form of its own calendar date, so it keys the same as the
          // day the balance walk builds with the same constructor.
          expect(
            date,
            dateOnly(date),
            reason: 'occurrences are canonical calendar dates',
          );
          expect(date.isBefore(dateOnly(from)), isFalse);
          expect(date.isAfter(dateOnly(to)), isFalse);
          expect(date.isBefore(dateOnly(start)), isFalse);
        }
        for (var j = 1; j < dates.length; j++) {
          expect(dates[j].isAfter(dates[j - 1]), isTrue);
        }
      }
    });

    test('a 31st monthly start never lands twice in one month', () {
      final dates = occurrencesBetween(
        _op(schedule: Schedule.monthly, startDate: DateTime(2026, 1, 31)),
        DateTime(2026),
        DateTime(2027, 12, 31),
      );
      final months = dates.map((d) => '${d.year}-${d.month}').toList();
      expect(months.toSet().length, months.length);
      expect(months.length, 24);
    });
  });
}
