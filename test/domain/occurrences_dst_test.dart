import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/projection/occurrences.dart';
import 'package:beaver_v2/domain/projection/project_balance.dart';
import 'package:beaver_v2/domain/projection/rate_table.dart';
import 'package:flutter_test/flutter_test.dart';

/// Occurrence dates are calendar dates: they must stay at local midnight even
/// when the window crosses a daylight-saving transition. The app runs in the
/// user's own time zone (web and Android), so most of Europe and the Americas
/// hit a transition twice a year — and `projectBalance` keys its per-day deltas
/// by the exact [DateTime], so an occurrence that is an hour off midnight simply
/// stops counting.
///
/// These tests need a local zone that actually has DST, so they are skipped in
/// UTC-like zones. Reproduce with `TZ=Europe/Berlin flutter test`.
void main() {
  final transition = _findLocalDstTransition();
  final skipReason = transition == null
      ? 'local time zone (${DateTime.now().timeZoneName}) has no DST transition'
      : null;

  // The day before the transition day, so the window straddles it.
  final windowFrom = transition == null
      ? DateTime(2026)
      : DateTime(transition.year, transition.month, transition.day - 2);
  final windowTo = DateTime(
    windowFrom.year,
    windowFrom.month,
    windowFrom.day + 5,
  );
  // The day after the transition: a window opening here has the transition
  // behind it, which is what breaks the weekly alignment.
  final weeklyFrom = transition == null
      ? DateTime(2026)
      : DateTime(transition.year, transition.month, transition.day + 1);

  Account account(int balance) => Account(
    id: 'a1',
    userId: 'u1',
    name: 'Карта',
    currencyCode: 'RUB',
    balance: balance,
  );

  PlannedOp op(Schedule schedule, DateTime startDate) => PlannedOp(
    id: 'op1',
    userId: 'u1',
    title: 'Обед',
    amount: 10000,
    currencyCode: 'RUB',
    kind: OpKind.expense,
    schedule: schedule,
    startDate: startDate,
  );

  group('occurrencesBetween across a DST transition', () {
    test('every daily occurrence stays at local midnight', () {
      final dates = occurrencesBetween(
        op(Schedule.daily, windowFrom),
        windowFrom,
        windowTo,
      );

      for (final date in dates) {
        expect(
          date,
          dateOnly(date),
          reason: '$date is not local midnight, so it cannot match a day key',
        );
      }
    }, skip: skipReason);

    test('a daily series covers every day of the window, inclusive', () {
      final dates = occurrencesBetween(
        op(Schedule.daily, windowFrom),
        windowFrom,
        windowTo,
      );

      expect(dates.length, 6);
      expect(dates.first, windowFrom);
      expect(dates.last, windowTo);
    }, skip: skipReason);

    test('a biweekly series keeps a 14-day step and stays at midnight', () {
      final from = DateTime(windowFrom.year, windowFrom.month, windowFrom.day);
      final to = DateTime(from.year, from.month, from.day + 42);
      final dates = occurrencesBetween(op(Schedule.biweekly, from), from, to);

      expect(dates, hasLength(4));
      for (var i = 0; i < dates.length; i++) {
        expect(dates[i], dateOnly(dates[i]));
        // Calendar days, so the 23- or 25-hour day inside the window does not
        // drag the series an hour off its cadence.
        expect(daysBetween(from, dates[i]), i * 14);
      }
    }, skip: skipReason);

    test('a biweekly series never fires before the window start', () {
      // Same trap as the weekly case below: the anchor sits before the
      // transition, so the elapsed-day count the alignment uses is short by an
      // hour — with a 14-day period that is just as easy to round the wrong way.
      final from = DateTime(weeklyFrom.year, weeklyFrom.month, weeklyFrom.day);
      final to = DateTime(from.year, from.month, from.day + 60);
      for (var offset = 1; offset <= 60; offset++) {
        final start = DateTime(from.year, from.month, from.day - offset);
        final dates = occurrencesBetween(
          op(Schedule.biweekly, start),
          from,
          to,
        );

        for (final date in dates) {
          expect(
            date.isBefore(from),
            isFalse,
            reason: 'start $start, window from $from: $date is outside it',
          );
          expect(date, dateOnly(date));
          expect(daysBetween(start, date) % 14, 0);
        }
      }
    }, skip: skipReason);

    test('a weekly series never fires before the window start', () {
      // The window opens just after the transition and the anchor sits before
      // it, so the elapsed-day count the alignment uses is short by an hour.
      final from = DateTime(weeklyFrom.year, weeklyFrom.month, weeklyFrom.day);
      final to = DateTime(from.year, from.month, from.day + 30);
      for (var offset = 1; offset <= 60; offset++) {
        final start = DateTime(from.year, from.month, from.day - offset);
        final dates = occurrencesBetween(op(Schedule.weekly, start), from, to);

        for (final date in dates) {
          expect(
            date.isBefore(from),
            isFalse,
            reason: 'start $start, window from $from: $date is outside it',
          );
          expect(date, dateOnly(date));
        }
      }
    }, skip: skipReason);
  });

  group('projectBalance across a DST transition', () {
    test('applies every daily occurrence to the balance', () {
      final result = projectBalance(
        accounts: [account(100000)],
        ops: [op(Schedule.daily, windowFrom)],
        from: windowFrom,
        to: windowTo,
        rates: RateTable.fromRates(const <Rate>[]),
        baseCurrency: 'RUB',
      );

      // Six days in the window, 100,00 ₽ a day: 1000,00 − 600,00 = 400,00.
      expect(result.events.length, 6);
      expect(result.startBalance, 100000);
      expect(result.endBalance, 40000);
      expect(result.points.last.balanceMinor, 40000);
    }, skip: skipReason);

    test('every event lands on a day that exists in points', () {
      final result = projectBalance(
        accounts: [account(100000)],
        ops: [op(Schedule.daily, windowFrom)],
        from: windowFrom,
        to: windowTo,
        rates: RateTable.fromRates(const <Rate>[]),
        baseCurrency: 'RUB',
      );

      final days = result.points.map((point) => point.date).toSet();
      for (final event in result.events) {
        expect(
          days.contains(event.date),
          isTrue,
          reason: '${event.date} has no matching point, so it is never applied',
        );
      }
    }, skip: skipReason);
  });
}

/// First local date in this year or the next whose midnight-to-midnight gap is
/// not 24 hours — i.e. the day a DST transition happens. `null` in zones without
/// DST (UTC, Asia/Tbilisi, Europe/Moscow…).
DateTime? _findLocalDstTransition() {
  final start = DateTime(DateTime.now().year);
  for (var i = 0; i < 730; i++) {
    final day = DateTime(start.year, start.month, start.day + i);
    final next = DateTime(day.year, day.month, day.day + 1);
    if (next.difference(day) != const Duration(hours: 24)) return day;
  }
  return null;
}
