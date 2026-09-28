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
}
