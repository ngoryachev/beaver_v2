import 'package:intl/intl.dart';

import '../../domain/models/currency.dart';
import '../../domain/models/money.dart';

/// Formats [minor] minor units of [code] for display, e.g. `1 234,56 ₽`.
///
/// Grouping and the decimal comma come from the `ru` locale; the symbol is
/// appended by hand so an unknown code still renders as `1 234,56 XYZ`.
String formatMoney(int minor, String code, {bool withSymbol = true}) {
  final currency = Currency.byCode(code);
  final pattern = currency.decimals == 0 ? '#,##0' : '#,##0.00';
  final text = NumberFormat(
    pattern,
    'ru',
  ).format(Money(minor, decimals: currency.decimals).major);
  return withSymbol ? '$text ${currency.symbol}' : text;
}

/// Same as [formatMoney] but without the fractional part — for chart axes and
/// other places where two decimals are just noise.
String formatMoneyCompact(int minor, String code, {bool withSymbol = true}) {
  final currency = Currency.byCode(code);
  final major = Money(minor, decimals: currency.decimals).major;
  final text = NumberFormat('#,##0', 'ru').format(major);
  return withSymbol ? '$text ${currency.symbol}' : text;
}

/// Plain editable text: no grouping, no symbol, comma as the decimal separator —
/// what a text field is prefilled with.
String moneyToInput(int minor, String code) {
  final decimals = Currency.decimalsOf(code);
  if (decimals == 0) return minor.toString();
  final major = Money(minor, decimals: decimals).major;
  return major
      .toStringAsFixed(decimals)
      .replaceAll('.', ',')
      // A whole amount reads better without a trailing `,00`.
      .replaceFirst(RegExp(r',0+$'), '');
}

/// `21.03.2026`.
String formatDate(DateTime date) => DateFormat('dd.MM.yyyy', 'ru').format(date);

/// `21 марта` — for event lists, where the year is implied.
String formatDayMonth(DateTime date) => DateFormat('d MMMM', 'ru').format(date);

/// Formats an exchange rate for display.
///
/// The APIs return eight decimal places; showing them all is noise. Small rates
/// (a euro per dollar) still need precision, large ones (a yen per dollar) do not.
String formatRate(double ratePerUsd) {
  final decimals = ratePerUsd >= 100
      ? 2
      : ratePerUsd >= 1
      ? 4
      : 6;
  return NumberFormat('#,##0.${'#' * decimals}', 'ru').format(ratePerUsd);
}
