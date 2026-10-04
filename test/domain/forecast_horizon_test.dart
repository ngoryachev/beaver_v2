import 'package:beaver_v2/domain/models/forecast_horizon.dart';
import 'package:beaver_v2/domain/projection/occurrences.dart';
import 'package:flutter_test/flutter_test.dart';

/// The horizon is stored now, so it is read back on a day other than the one it
/// was chosen on. These are the rules that follow from that: what counts as
/// expired, and the date-only guarantee `projectionProvider`'s family cache
/// depends on.
void main() {
  final today = DateTime(2026, 10, 4, 13, 45);

  group('isExpired', () {
    test('a date behind us is expired', () {
      final horizon = ForecastHorizon(
        preset: ForecastPreset.custom,
        customDate: DateTime(2026, 10, 3),
      );
      expect(horizon.isExpired(today), isTrue);
    });

    test('today is not expired yet', () {
      // `isBefore`, not `isAfter`: the day the user picked is theirs until it
      // ends, and a window of today..today is a horizon they asked for.
      final horizon = ForecastHorizon(
        preset: ForecastPreset.custom,
        customDate: DateTime(2026, 10, 4),
      );
      expect(horizon.isExpired(today), isFalse);
    });

    test('compares dates, not instants', () {
      // Midnight today against a quarter to two in the afternoon: an instant
      // comparison would call this expired and throw the choice away mid-day.
      final horizon = ForecastHorizon(
        preset: ForecastPreset.custom,
        customDate: dateOnly(today),
      );
      expect(horizon.isExpired(today), isFalse);
    });

    test('a future date is not expired', () {
      final horizon = ForecastHorizon(
        preset: ForecastPreset.custom,
        customDate: DateTime(2027, 1, 1),
      );
      expect(horizon.isExpired(today), isFalse);
    });

    test('a custom preset with no date is not expired', () {
      expect(
        const ForecastHorizon(preset: ForecastPreset.custom).isExpired(today),
        isFalse,
      );
    });

    test('a preset horizon is never expired, stale date or not', () {
      // The date rides along through a detour to another preset, so a stored
      // one can be years old while the active preset is relative.
      final horizon = ForecastHorizon(
        preset: ForecastPreset.plus90,
        customDate: DateTime(2020, 1, 1),
      );
      expect(horizon.isExpired(today), isFalse);
      expect(horizon.targetDate(today), DateTime(2027, 1, 2));
    });
  });

  group('targetDate', () {
    test('is date-only for every preset', () {
      // The value keys `projectionProvider`'s family cache: a time component
      // would leave a dead projection behind on every rebuild.
      for (final horizon in [
        const ForecastHorizon(preset: ForecastPreset.endOfMonth),
        const ForecastHorizon(preset: ForecastPreset.plus30),
        const ForecastHorizon(preset: ForecastPreset.plus90),
        const ForecastHorizon(preset: ForecastPreset.custom),
        ForecastHorizon(
          preset: ForecastPreset.custom,
          // A stored date that carries a time, as a hand-written row might.
          customDate: DateTime(2026, 12, 31, 18, 30),
        ),
      ]) {
        final target = horizon.targetDate(today);
        expect(
          target,
          DateTime(target.year, target.month, target.day),
          reason: '${horizon.preset} must return a date-only value',
        );
      }
    });

    test('end of month lands on the last day of the current month', () {
      expect(
        const ForecastHorizon(
          preset: ForecastPreset.endOfMonth,
        ).targetDate(DateTime(2026, 2, 10)),
        DateTime(2026, 2, 28),
      );
      expect(
        const ForecastHorizon(
          preset: ForecastPreset.endOfMonth,
        ).targetDate(DateTime(2024, 2, 10)),
        DateTime(2024, 2, 29),
      );
    });

    test('the presets count calendar days', () {
      expect(
        const ForecastHorizon().targetDate(today),
        addDays(dateOnly(today), 30),
      );
      expect(
        const ForecastHorizon(
          preset: ForecastPreset.plus90,
        ).targetDate(today),
        addDays(dateOnly(today), 90),
      );
    });

    test('a custom preset with no date behaves like +30 дней', () {
      expect(
        const ForecastHorizon(preset: ForecastPreset.custom).targetDate(today),
        const ForecastHorizon(preset: ForecastPreset.plus30).targetDate(today),
      );
    });
  });

  group('fromWire', () {
    test('reads back every preset it writes', () {
      for (final preset in ForecastPreset.values) {
        expect(ForecastPreset.fromWire(preset.wire), preset);
      }
    });

    test('an unknown or missing value falls back to the default', () {
      // A newer build may have written the column; an unreadable horizon must
      // not take the settings row — and with it the base currency — down.
      expect(ForecastPreset.fromWire('quarter'), ForecastPreset.plus30);
      expect(ForecastPreset.fromWire(null), ForecastPreset.plus30);
      expect(ForecastPreset.fromWire(''), ForecastPreset.plus30);
    });
  });
}
