import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/projection/rate_table.dart';
import 'package:flutter_test/flutter_test.dart';

Rate _rate(
  String code,
  double perUsd, {
  RateSource source = RateSource.auto,
  DateTime? updatedAt,
}) => Rate(
  userId: 'u1',
  code: code,
  ratePerUsd: perUsd,
  source: source,
  updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
);

void main() {
  group('RateTable', () {
    test('USD is always available as the pivot', () {
      final table = RateTable.fromRates(const []);

      expect(table.rateFor('USD'), 1);
      expect(table.has('RUB'), isFalse);
    });

    test('converts through USD as a cross-rate', () {
      // 90 RUB and 0.9 EUR per USD → 100 RUB is 1 EUR.
      final table = RateTable.fromRates([_rate('RUB', 90), _rate('EUR', 0.9)]);

      expect(table.convertMinor(10000, from: 'RUB', to: 'EUR'), 100);
      expect(table.convertMinor(100, from: 'EUR', to: 'RUB'), 10000);
    });

    test('converts to and from the USD pivot itself', () {
      final table = RateTable.fromRates([_rate('RUB', 80)]);

      expect(table.convertMinor(8000, from: 'RUB', to: 'USD'), 100);
      expect(table.convertMinor(100, from: 'USD', to: 'RUB'), 8000);
    });

    test('same currency is returned untouched even without a rate', () {
      final table = RateTable.fromRates(const []);

      expect(table.convertMinor(12345, from: 'KZT', to: 'KZT'), 12345);
    });

    test('manual rate wins over auto regardless of timestamp', () {
      final table = RateTable.fromRates([
        _rate('RUB', 90, updatedAt: DateTime.utc(2026, 6, 1)),
        _rate(
          'RUB',
          100,
          source: RateSource.manual,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);

      expect(table.rateFor('RUB'), 100);
    });

    test('manual rate wins whichever order the rows arrive in', () {
      final table = RateTable.fromRates([
        _rate('RUB', 100, source: RateSource.manual),
        _rate('RUB', 90),
      ]);

      expect(table.rateFor('RUB'), 100);
    });

    test('among rows of the same source the newest wins', () {
      final table = RateTable.fromRates([
        _rate('RUB', 90, updatedAt: DateTime.utc(2026, 1, 1)),
        _rate('RUB', 95, updatedAt: DateTime.utc(2026, 2, 1)),
      ]);

      expect(table.rateFor('RUB'), 95);
    });

    test('an unknown rate yields null, not zero', () {
      final table = RateTable.fromRates([_rate('RUB', 90)]);

      expect(table.convertMinor(10000, from: 'KZT', to: 'RUB'), isNull);
      expect(table.convertMinor(10000, from: 'RUB', to: 'KZT'), isNull);
      expect(table.missing(['RUB', 'KZT', 'GEL']), {'KZT', 'GEL'});
    });

    test('honours differing minor-unit precision', () {
      // JPY has 0 decimals: 150 JPY per USD means 1.00 USD → 150 JPY.
      final table = RateTable.fromRates([_rate('JPY', 150)]);

      expect(table.convertMinor(100, from: 'USD', to: 'JPY'), 150);
      expect(table.convertMinor(150, from: 'JPY', to: 'USD'), 100);
    });

    test('ignores non-positive rates', () {
      final table = RateTable.fromRates([_rate('RUB', 0), _rate('EUR', -1)]);

      expect(table.has('RUB'), isFalse);
      expect(table.has('EUR'), isFalse);
    });
  });
}
