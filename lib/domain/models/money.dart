/// Money is always an `int` count of minor units (kopecks, cents). Doubles are
/// reserved for exchange rates — see [RateTable].
///
/// The type itself is a thin wrapper holding the parsing, rounding and scaling
/// rules; the models store the raw `int`. Everything that needs to cross between
/// major and minor units goes through here, so the scale factor is defined once.
class Money {
  /// Amount in minor units. May be negative (a balance can go below zero).
  final int minor;

  /// Number of minor digits the amount is expressed in (2 for RUB/USD, 0 for JPY).
  final int decimals;

  const Money(this.minor, {this.decimals = 2});

  /// Builds a value from a major-unit amount, rounding to the nearest minor unit.
  factory Money.fromMajor(double major, {int decimals = 2}) =>
      Money((major * _pow10(decimals)).round(), decimals: decimals);

  /// Matches an optionally signed decimal: `-12`, `1234.56`, `.5`, `7.`.
  static final _decimal = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?$');

  /// Turns a number as a Russian user types it into something `num.parse` and
  /// [tryParse] can read: drops grouping spaces (the formatter emits a
  /// non-breaking one) and accepts a decimal comma.
  ///
  /// Shared with the exchange-rate field, which is a `double` rather than money
  /// but is typed the same way.
  static String normalizeDecimalInput(String text) =>
      text.replaceAll(' ', '').replaceAll(' ', '').replaceAll(',', '.').trim();

  /// Parses a human string such as `1 234,56` or `-12.3`. Returns `null` when
  /// the text is not a number, so callers can show a validation error.
  ///
  /// The digits are scaled by hand rather than through `double`: `1,005 * 100`
  /// is `100.49999...` in binary floating point, which would round a user's
  /// input *down* a kopeck.
  static Money? tryParse(String text, {int decimals = 2}) {
    final match = _decimal.firstMatch(normalizeDecimalInput(text));
    if (match == null) return null;

    final whole = match.group(2) ?? '';
    final fraction = match.group(3) ?? '';
    // Rejects '', '-', '.' and '+.' — a sign or a point alone is not an amount.
    if (whole.isEmpty && fraction.isEmpty) return null;

    final units = int.tryParse(whole.isEmpty ? '0' : whole);
    if (units == null) return null;

    // One digit past the currency's precision is enough to round half-up.
    final padded = fraction.padRight(decimals + 1, '0');
    final kept = decimals == 0
        ? 0
        : int.tryParse(padded.substring(0, decimals));
    if (kept == null) return null;
    final roundUp = padded.codeUnitAt(decimals) >= _zero + 5;

    final minor = units * _pow10(decimals) + kept + (roundUp ? 1 : 0);
    return Money(match.group(1) == '-' ? -minor : minor, decimals: decimals);
  }

  static const _zero = 0x30;

  /// Amount expressed in major units, for display and rate arithmetic only.
  double get major => minor / _pow10(decimals);

  /// 10^[exponent]: the scale between major and minor units.
  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.decimals == decimals;

  @override
  int get hashCode => Object.hash(minor, decimals);

  @override
  String toString() => 'Money($minor, decimals: $decimals)';
}
