import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/projection/occurrences.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// `2026-02-28` → `28.02` — keeps the expectations readable.
List<String> _fmt(List<DateTime> dates) => dates
    .map(
      (d) =>
          '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}',
    )
    .toList();

void main() {
  group('occurrencesBetween — once', () {
    test('fires exactly once when the date is inside the window', () {
      final op = _op(schedule: Schedule.once, startDate: DateTime(2026, 3, 10));

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 31),
      );

      expect(_fmt(dates), ['10.03.2026']);
    });

    test('does not fire when the date is before the window', () {
      final op = _op(schedule: Schedule.once, startDate: DateTime(2026, 2, 10));

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 31),
      );

      expect(dates, isEmpty);
    });

    test('does not fire when the date is after the window', () {
      final op = _op(schedule: Schedule.once, startDate: DateTime(2026, 4, 10));

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 31),
      );

      expect(dates, isEmpty);
    });

    test('fires on the window boundaries, inclusive', () {
      final atFrom = _op(
        schedule: Schedule.once,
        startDate: DateTime(2026, 3, 1),
      );
      final atTo = _op(
        schedule: Schedule.once,
        startDate: DateTime(2026, 3, 31),
      );

      expect(
        occurrencesBetween(atFrom, DateTime(2026, 3, 1), DateTime(2026, 3, 31)),
        hasLength(1),
      );
      expect(
        occurrencesBetween(atTo, DateTime(2026, 3, 1), DateTime(2026, 3, 31)),
        hasLength(1),
      );
    });

    test('ignores the time part of the start date', () {
      final op = _op(
        schedule: Schedule.once,
        startDate: DateTime(2026, 3, 31, 23, 59),
      );

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 31),
      );

      expect(_fmt(dates), ['31.03.2026']);
    });
  });

  group('occurrencesBetween — daily', () {
    test('fires on every day of the window', () {
      final op = _op(schedule: Schedule.daily, startDate: DateTime(2026, 3, 1));

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 10),
      );

      expect(dates, hasLength(10));
      expect(_fmt(dates).first, '01.03.2026');
      expect(_fmt(dates).last, '10.03.2026');
    });

    test('a start before the window does not produce dates before it', () {
      final op = _op(schedule: Schedule.daily, startDate: DateTime(2026, 1, 1));

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 3, 5),
        DateTime(2026, 3, 7),
      );

      expect(_fmt(dates), ['05.03.2026', '06.03.2026', '07.03.2026']);
    });

    test('starts mid-window when the start date falls inside it', () {
      final op = _op(schedule: Schedule.daily, startDate: DateTime(2026, 3, 8));

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 3, 5),
        DateTime(2026, 3, 10),
      );

      expect(_fmt(dates), ['08.03.2026', '09.03.2026', '10.03.2026']);
    });
  });

  group('occurrencesBetween — weekly', () {
    test('keeps a 7-day cadence anchored on the start date', () {
      final op = _op(
        schedule: Schedule.weekly,
        startDate: DateTime(2026, 3, 2),
      );

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 31),
      );

      expect(_fmt(dates), [
        '02.03.2026',
        '09.03.2026',
        '16.03.2026',
        '23.03.2026',
        '30.03.2026',
      ]);
    });

    test('stays on the anchor weekday when the window starts later', () {
      final op = _op(
        schedule: Schedule.weekly,
        startDate: DateTime(2026, 1, 5),
      );

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 20),
      );

      // 05.01 is a Monday; every listed date must be a Monday too.
      expect(dates.every((d) => d.weekday == DateTime.monday), isTrue);
      expect(_fmt(dates), ['02.03.2026', '09.03.2026', '16.03.2026']);
    });
  });

  group('occurrencesBetween — monthly', () {
    test('keeps the same day of month', () {
      final op = _op(
        schedule: Schedule.monthly,
        startDate: DateTime(2026, 1, 15),
      );

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 1, 1),
        DateTime(2026, 4, 30),
      );

      expect(_fmt(dates), [
        '15.01.2026',
        '15.02.2026',
        '15.03.2026',
        '15.04.2026',
      ]);
    });

    test('a 31st start clamps to the last day of February', () {
      final op = _op(
        schedule: Schedule.monthly,
        startDate: DateTime(2026, 1, 31),
      );

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 1, 1),
        DateTime(2026, 2, 28),
      );

      expect(_fmt(dates), ['31.01.2026', '28.02.2026']);
    });

    test('a 31st start returns to the 31st after a short month', () {
      final op = _op(
        schedule: Schedule.monthly,
        startDate: DateTime(2026, 1, 31),
      );

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 1, 1),
        DateTime(2026, 5, 31),
      );

      expect(_fmt(dates), [
        '31.01.2026',
        '28.02.2026',
        '31.03.2026',
        '30.04.2026',
        '31.05.2026',
      ]);
    });

    test('a 31st start clamps to 29 February in a leap year', () {
      final op = _op(
        schedule: Schedule.monthly,
        startDate: DateTime(2028, 1, 31),
      );

      final dates = occurrencesBetween(
        op,
        DateTime(2028, 2, 1),
        DateTime(2028, 2, 29),
      );

      expect(_fmt(dates), ['29.02.2028']);
    });

    test('a start before the window is not skipped or duplicated', () {
      final op = _op(
        schedule: Schedule.monthly,
        startDate: DateTime(2025, 1, 10),
      );

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 3, 1),
        DateTime(2026, 5, 31),
      );

      expect(_fmt(dates), ['10.03.2026', '10.04.2026', '10.05.2026']);
    });

    test(
      'a start on the 1st with a window opening on the 1st fires that day',
      () {
        final op = _op(
          schedule: Schedule.monthly,
          startDate: DateTime(2025, 6, 1),
        );

        final dates = occurrencesBetween(
          op,
          DateTime(2026, 3, 1),
          DateTime(2026, 3, 31),
        );

        expect(_fmt(dates), ['01.03.2026']);
      },
    );
  });

  group('occurrencesBetween — yearly', () {
    test('fires once per year on the anchor date', () {
      final op = _op(
        schedule: Schedule.yearly,
        startDate: DateTime(2026, 5, 20),
      );

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 1, 1),
        DateTime(2029, 1, 1),
      );

      expect(_fmt(dates), ['20.05.2026', '20.05.2027', '20.05.2028']);
    });

    test('never fires before the start year', () {
      final op = _op(
        schedule: Schedule.yearly,
        startDate: DateTime(2027, 5, 20),
      );

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31),
      );

      expect(dates, isEmpty);
    });

    test('a 29 February anchor clamps to 28 February in common years', () {
      final op = _op(
        schedule: Schedule.yearly,
        startDate: DateTime(2028, 2, 29),
      );

      final dates = occurrencesBetween(
        op,
        DateTime(2028, 1, 1),
        DateTime(2030, 12, 31),
      );

      expect(_fmt(dates), ['29.02.2028', '28.02.2029', '28.02.2030']);
    });
  });

  group('occurrencesBetween — end_date', () {
    test('truncates the series', () {
      final op = _op(
        schedule: Schedule.daily,
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 5),
      );

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 31),
      );

      expect(dates, hasLength(5));
      expect(_fmt(dates).last, '05.03.2026');
    });

    test('is inclusive of the end date itself', () {
      final op = _op(
        schedule: Schedule.monthly,
        startDate: DateTime(2026, 1, 15),
        endDate: DateTime(2026, 3, 15),
      );

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31),
      );

      expect(_fmt(dates), ['15.01.2026', '15.02.2026', '15.03.2026']);
    });

    test('an end date before the window yields nothing', () {
      final op = _op(
        schedule: Schedule.daily,
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 2, 1),
      );

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 31),
      );

      expect(dates, isEmpty);
    });
  });

  group('occurrencesBetween — degenerate windows', () {
    test('an inverted window yields nothing', () {
      final op = _op(schedule: Schedule.daily, startDate: DateTime(2026, 1, 1));

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 3, 10),
        DateTime(2026, 3, 1),
      );

      expect(dates, isEmpty);
    });

    test('a single-day window still fires', () {
      final op = _op(schedule: Schedule.daily, startDate: DateTime(2026, 1, 1));

      final dates = occurrencesBetween(
        op,
        DateTime(2026, 3, 10),
        DateTime(2026, 3, 10),
      );

      expect(_fmt(dates), ['10.03.2026']);
    });
  });

  group('daysInMonth', () {
    test('handles February in leap and common years', () {
      expect(daysInMonth(2026, 2), 28);
      expect(daysInMonth(2028, 2), 29);
      expect(daysInMonth(2026, 1), 31);
      expect(daysInMonth(2026, 4), 30);
      expect(daysInMonth(2026, 12), 31);
    });
  });
}
