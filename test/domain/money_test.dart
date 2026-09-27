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
