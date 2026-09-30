import 'package:beaver_v2/data/supabase/date_wire.dart';
import 'package:flutter_test/flutter_test.dart';

/// `start_date` and `end_date` are Postgres `DATE` columns: they must cross the
/// wire as the calendar day the user picked, whatever the device's time zone and
/// whatever time of day the [DateTime] happens to carry.
void main() {
  group('dateToWire', () {
    test('is YYYY-MM-DD, zero-padded', () {
      expect(dateToWire(DateTime(2026, 3, 1)), '2026-03-01');
      expect(dateToWire(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('ignores the time component instead of rolling the day over', () {
      expect(dateToWire(DateTime(2026, 3, 1, 23, 59, 59)), '2026-03-01');
      expect(dateToWire(DateTime(2026, 3, 1, 0, 0, 1)), '2026-03-01');
    });
  });

  group('dateFromWire', () {
    test('parses a bare date into local midnight', () {
      final parsed = dateFromWire('2026-03-01');
      expect(parsed, DateTime(2026, 3, 1));
      expect(parsed.isUtc, isFalse);
      expect(parsed.hour, 0);
    });

    test('round-trips every day of a leap February', () {
      for (var day = 1; day <= 29; day++) {
        final date = DateTime(2028, 2, day);
        expect(dateFromWire(dateToWire(date)), date);
      }
    });

    test('drops a time component the server may add', () {
      expect(dateFromWire('2026-03-01T00:00:00'), DateTime(2026, 3, 1));
    });
  });

  // PostgREST hands back a non-finite `double precision` as a JSON *string*.
  // A plain `as num` cast throws on it, which fails the whole rates query and
  // leaves the app with no rates at all — and no «Сбросить» button to remove
  // the offending row, because settings builds that from the loaded rows.
  group('rateFromWire', () {
    test('reads an ordinary number', () {
      expect(rateFromWire(84.38), 84.38);
      expect(rateFromWire(90), 90.0);
    });

    test('reads the string form Postgres uses for non-finite values', () {
      expect(rateFromWire('Infinity'), double.infinity);
      expect(rateFromWire('-Infinity'), double.negativeInfinity);
      expect(rateFromWire('NaN').isNaN, isTrue);
    });

    test('reads a number that arrived as a string', () {
      expect(rateFromWire('84.38'), 84.38);
    });

    test('turns anything unrecognisable into NaN rather than throwing', () {
      expect(rateFromWire(null).isNaN, isTrue);
      expect(rateFromWire('нет').isNaN, isTrue);
      expect(rateFromWire(<String, Object>{}).isNaN, isTrue);
    });

    test('never throws, whatever the column holds', () {
      for (final value in <Object?>[
        null,
        'Infinity',
        'NaN',
        '',
        true,
        [1],
        84.38,
      ]) {
        expect(() => rateFromWire(value), returnsNormally, reason: '$value');
      }
    });
  });
}
