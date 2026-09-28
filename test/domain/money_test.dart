import 'package:beaver_v2/domain/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.tryParse', () {
    test('accepts a decimal comma, as Russian input uses', () {
      expect(Money.tryParse('1234,56')?.minor, 123456);
    });

    test('accepts a decimal point too', () {
      expect(Money.tryParse('1234.56')?.minor, 123456);
    });

    test('ignores plain and non-breaking spaces from formatted text', () {
      // formatMoney emits a non-breaking space as the group separator, so a
      // round trip through a text field has to survive it.
      expect(Money.tryParse('1 234 567,89')?.minor, 123456789);
    });

    test('parses a whole number', () {
      expect(Money.tryParse('250')?.minor, 25000);
    });

    test('parses a negative amount', () {
      expect(Money.tryParse('-12,3')?.minor, -1230);
    });

    test('rounds beyond the currency precision rather than truncating', () {
      expect(Money.tryParse('1,005')?.minor, 101);
      expect(Money.tryParse('1,004')?.minor, 100);
    });

    test('honours a zero-decimal currency', () {
      expect(Money.tryParse('1500', decimals: 0)?.minor, 1500);
      expect(Money.tryParse('1500,7', decimals: 0)?.minor, 1501);
    });

    test('returns null for text that is not a number', () {
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('   '), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse(','), isNull);
    });

    test('returns null for infinity and NaN', () {
      expect(Money.tryParse('Infinity'), isNull);
      expect(Money.tryParse('NaN'), isNull);
    });
  });

  // Also used by the exchange-rate field in settings, which feeds the result to
  // `double.tryParse` — so it is worth pinning on its own.
  group('Money.normalizeDecimalInput', () {
    test('turns a decimal comma into a point', () {
      expect(Money.normalizeDecimalInput('0,91'), '0.91');
    });

    test('drops grouping spaces, plain and non-breaking', () {
      expect(Money.normalizeDecimalInput('1 234,56'), '1234.56');
      expect(Money.normalizeDecimalInput('1\u00a0234,56'), '1234.56');
    });

    test('trims surrounding whitespace', () {
      expect(Money.normalizeDecimalInput('  84,38  '), '84.38');
    });

    test('leaves an already-normal number alone', () {
      expect(Money.normalizeDecimalInput('84.38308093'), '84.38308093');
    });

    test('produces something double.tryParse accepts', () {
      expect(double.tryParse(Money.normalizeDecimalInput('1 234,56')), 1234.56);
      expect(double.tryParse(Money.normalizeDecimalInput('нет')), isNull);
    });
  });

  // Scaling to minor units silently corrupts an amount that does not fit, so
  // the parser refuses anything past [Money.maxMinor]. The boundary is exact
  // rather than a round guess, and the check runs *before* multiplying —
  // afterwards the corruption is indistinguishable from a real number.
  group('Money.tryParse at the representable boundary', () {
    test('maxMinor is 2^53, the limit both targets hold exactly', () {
      // Not int64 max: on the web an `int` is a JS double, and the web build is
      // the deployed one. A larger literal does not even compile for it.
      expect(Money.maxMinor, 9007199254740992);
    });

    test('accepts the largest representable amount, to the kopeck', () {
      expect(Money.tryParse('90071992547409.92')?.minor, Money.maxMinor);
      expect(Money.tryParse('-90071992547409.92')?.minor, -Money.maxMinor);
    });

    test('refuses one kopeck past it', () {
      expect(Money.tryParse('90071992547409.93'), isNull);
      expect(Money.tryParse('90071992547410'), isNull);
    });

    test('counts the rounding carry against the limit', () {
      // .924 rounds down and still fits; .925 would round up past the end.
      expect(Money.tryParse('90071992547409.924')?.minor, Money.maxMinor);
      expect(Money.tryParse('90071992547409.925'), isNull);
    });

    test('a long amount never comes back negative or altered', () {
      for (final digits in [13, 14, 15, 16, 17, 18, 20, 25]) {
        final text = '9' * digits;
        final parsed = Money.tryParse(text);
        if (parsed == null) continue;

        expect(parsed.minor, greaterThan(0), reason: '$digits digits');
        // Compared in minor units, not via `major`: that getter goes through
        // `double`, which cannot hold these magnitudes exactly.
        expect(
          parsed.minor,
          int.parse(text) * 100,
          reason: '$digits digits must scale exactly',
        );
      }
    });

    test('a zero-decimal currency has the same limit, without scaling', () {
      expect(
        Money.tryParse('9007199254740992', decimals: 0)?.minor,
        Money.maxMinor,
      );
      expect(Money.tryParse('9007199254740993', decimals: 0), isNull);
    });

    test('ordinary amounts are untouched by the guard', () {
      expect(Money.tryParse('1234,56')?.minor, 123456);
      expect(Money.tryParse('0,01')?.minor, 1);
      expect(Money.tryParse('1000000')?.minor, 100000000);
    });
  });

  group('Money scaling', () {
    test('major and fromMajor are inverse', () {
      const money = Money(123456);
      expect(money.major, 1234.56);
      expect(Money.fromMajor(money.major).minor, money.minor);
    });

    test('a zero-decimal currency has no fractional part', () {
      expect(const Money(1500, decimals: 0).major, 1500);
      expect(Money.fromMajor(1500.4, decimals: 0).minor, 1500);
    });

    test('a negative amount scales symmetrically', () {
      expect(const Money(-5000).major, -50);
      expect(Money.fromMajor(-50).minor, -5000);
    });
  });

  group('Money equality', () {
    test('same amount and precision are equal', () {
      expect(const Money(100), const Money(100));
    });

    test('the same minor count at a different precision is not equal', () {
      // 100 kopecks is not 100 yen, so the precision is part of the identity.
      expect(const Money(100), isNot(const Money(100, decimals: 0)));
    });
  });
}
