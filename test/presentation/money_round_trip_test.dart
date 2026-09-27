import 'package:beaver_v2/domain/models/currency.dart';
import 'package:beaver_v2/domain/models/money.dart';
import 'package:beaver_v2/presentation/format/money_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// [TransferSheet] prefills the credited field with [moneyToInput] and parses
/// that same text back with [Money.tryParse] on submit, so the two have to be
/// exact inverses — a lost kopeck here is a wrong balance in the database.
///
/// [formatMoney] is display-only, but the user can retype what they see, so it
/// has to survive the same round trip.
void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  const amounts = <int>[
    0,
    1,
    5,
    50,
    99,
    100,
    101,
    999,
    1000,
    100000,
    123456789,
    -1,
    -50,
    -123456789,
  ];

  group('moneyToInput is the inverse of Money.tryParse', () {
    for (final code in ['RUB', 'USD', 'JPY', 'XYZ']) {
      test('for $code', () {
        final decimals = Currency.decimalsOf(code);
        for (final minor in amounts) {
          final text = moneyToInput(minor, code);
          final parsed = Money.tryParse(text, decimals: decimals);

          expect(
            parsed?.minor,
            minor,
            reason: '$minor $code rendered as "$text" parsed back differently',
          );
        }
      });
    }
  });

  group('formatMoney survives being retyped', () {
    for (final code in ['RUB', 'JPY', 'XYZ']) {
      test('for $code', () {
        final decimals = Currency.decimalsOf(code);
        for (final minor in amounts) {
          // The symbol is not part of an amount, so it is stripped the way the
          // user would: what is left is the grouped number the `ru` locale made.
          final text = formatMoney(minor, code, withSymbol: false);
          final parsed = Money.tryParse(text, decimals: decimals);

          expect(
            parsed?.minor,
            minor,
            reason:
                '$minor $code formatted as "$text" '
                '(separators: ${text.runes.where((r) => r > 127).map((r) => r.toRadixString(16)).toList()}) '
                'did not parse back',
          );
        }
      });
    }
  });

  group('the digits a keypad can produce all parse', () {
    test('a bare decimal separator is a usable zero, not a crash', () {
      expect(Money.tryParse('0,')?.minor, 0);
    });

    test('a partially typed fraction parses as the user expects', () {
      expect(Money.tryParse('12,')?.minor, 1200);
      expect(Money.tryParse('12,5')?.minor, 1250);
      expect(Money.tryParse('12,05')?.minor, 1205);
    });

    test('a leading zero does not change the value', () {
      expect(Money.tryParse('007,50')?.minor, 750);
    });
  });
}
