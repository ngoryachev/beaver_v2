import 'package:beaver_v2/presentation/format/money_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('formatMoney', () {
    test('groups thousands and uses a decimal comma', () {
      expect(formatMoney(123456789, 'RUB'), '1 234 567,89 ₽');
    });

    test('omits the symbol on request', () {
      expect(formatMoney(100000, 'RUB', withSymbol: false), '1 000,00');
    });

    test('honours a zero-decimal currency', () {
      expect(formatMoney(1500, 'JPY'), '1 500 ¥');
    });

    test('renders a negative amount', () {
      expect(formatMoney(-50000, 'RUB'), '-500,00 ₽');
    });

    test('falls back to the code for an unknown currency', () {
      expect(formatMoney(10000, 'XYZ'), '100,00 XYZ');
    });
  });

  group('formatMoneyCompact', () {
    test('drops the fractional part', () {
      expect(formatMoneyCompact(123456789, 'RUB'), '1 234 568 ₽');
    });

    test('omits the symbol for chart axes', () {
      expect(formatMoneyCompact(45000000, 'RUB', withSymbol: false), '450 000');
    });
  });

  group('moneyToInput', () {
    test('drops a trailing zero fraction', () {
      expect(moneyToInput(100000, 'RUB'), '1000');
    });

    test('keeps a real fraction, comma-separated', () {
      expect(moneyToInput(123456, 'RUB'), '1234,56');
    });

    test('has no fraction for a zero-decimal currency', () {
      expect(moneyToInput(1500, 'JPY'), '1500');
    });

    test('keeps a trailing zero inside a real fraction', () {
      // Only a wholly-zero fraction is dropped: «88,50» reads as money, «88,5»
      // looks like a typo in an amount field.
      expect(moneyToInput(8850, 'EUR'), '88,50');
    });
  });

  // The whole UI reads dates through these two. They are pinned because the
  // Russian month names come from `intl`, whose constraint had to be raised to
  // ^0.20.2 to pull in flutter_localizations.
  group('formatDate', () {
    test('is day.month.year, zero-padded', () {
      expect(formatDate(DateTime(2026, 1, 5)), '05.01.2026');
      expect(formatDate(DateTime(2026, 12, 31)), '31.12.2026');
    });

    test('ignores any time component', () {
      expect(formatDate(DateTime(2026, 3, 21, 23, 59)), '21.03.2026');
    });
  });

  group('formatDayMonth', () {
    test('uses the Russian genitive month, without the year', () {
      expect(formatDayMonth(DateTime(2026, 3, 21)), '21 марта');
      expect(formatDayMonth(DateTime(2026, 1, 5)), '5 января');
      expect(formatDayMonth(DateTime(2026, 9, 1)), '1 сентября');
      expect(formatDayMonth(DateTime(2026, 12, 31)), '31 декабря');
    });

    test('does not zero-pad the day', () {
      expect(formatDayMonth(DateTime(2026, 5, 7)), '7 мая');
    });
  });

  group('formatRate', () {
    test('trims the API noise on a large rate', () {
      expect(formatRate(84.38308093), '84,3831');
    });

    test('keeps precision on a sub-1 rate', () {
      expect(formatRate(0.87786534), '0,877865');
    });

    test('uses two decimals past a hundred', () {
      expect(formatRate(512.34567), '512,35');
    });

    test('renders a whole rate without a fraction', () {
      expect(formatRate(90), '90');
    });
  });
}
