import 'package:beaver_v2/domain/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Money.tryParse` is the single gate between what a user types and the `int`
/// minor units the whole app stores. It already refuses `Infinity` and `NaN`
/// because an unrepresentable amount must not become a number — but the scaling
/// `units * 10^decimals` is plain 64-bit integer arithmetic, which wraps around
/// silently instead of refusing.
///
/// Nothing upstream caps the digit count: neither the balance keypad nor the
/// amount fields set `maxLength` or an input formatter, so the text reaching this
/// parser is whatever the user typed or pasted.
///
/// The limit is [Money.maxMinor] (2^53), not int64 max: on the web an `int` is a
/// JavaScript double, and the web build is the deployed one — an int64 bound
/// does not even compile for it.
void main() {
  group('Money.tryParse rejects an amount it cannot represent', () {
    test('a 17-digit amount does not wrap into a negative balance', () {
      // 99_999_999_999_999_999 roubles is 1e19 kopecks, past int64. The scaling
      // wraps and the result comes back as a large *negative* amount.
      final parsed = Money.tryParse('9' * 17);
      if (parsed != null) {
        expect(
          parsed.minor,
          greaterThan(0),
          reason:
              'a positive amount must never parse to a negative number of '
              'minor units',
        );
      }
    });

    test('an 18-digit amount does not wrap into a different amount', () {
      const text = '999999999999999999';
      final parsed = Money.tryParse(text);
      if (parsed != null) {
        // Whatever comes back has to say the same thing the user typed.
        expect(
          parsed.major.toStringAsFixed(0),
          text,
          reason: 'the parsed amount must match the typed one',
        );
      }
    });

    test('a zero-decimal currency has no scaling to overflow', () {
      // The counterexample that pins the cause: with decimals: 0 there is no
      // multiplication, so a hundredfold larger amount is still accepted where
      // the same digits with kopecks are not.
      expect(
        Money.tryParse('9007199254740992', decimals: 0)?.minor,
        9007199254740992,
      );
      expect(
        Money.tryParse('90071992547409', decimals: 2)?.minor,
        9007199254740900,
      );
      // The cap is on the *scaled* amount, so two decimals run out a hundred
      // times sooner than none.
      expect(Money.tryParse('9007199254740992', decimals: 2), isNull);
      expect(Money.tryParse('9' * 20, decimals: 0), isNull);
    });
  });
}
