import '../models/currency.dart';
import '../models/money.dart';
import '../models/rate.dart';

/// Converts amounts between currencies. All rates are quoted per USD, so a
/// cross-rate goes through USD: `base = amount / r[code] * r[base]`.
///
/// A manual rate always shadows the auto rate for the same code.
class RateTable {
  final Map<String, double> _rates;

  RateTable._(this._rates);

  /// Builds the table from stored rows. `manual` wins; among rows of the same
  /// source the most recent one wins.
  factory RateTable.fromRates(Iterable<Rate> rates) {
    final byCode = <String, Rate>{};
    for (final rate in rates) {
      final code = rate.code.toUpperCase();
      final existing = byCode[code];
      if (existing == null || _beats(rate, existing)) {
        byCode[code] = rate;
      }
    }
    // `isFinite` as well as `> 0`: the column is DOUBLE PRECISION under a
    // `CHECK (rate_per_usd > 0)`, which Postgres happily satisfies with
    // 'Infinity'. Letting one through makes every conversion *into* that
    // currency infinite, and `Money.fromMajor` then throws on `.round()` —
    // taking the home and forecast screens down. An unusable rate has to look
    // like a missing one.
    final table = <String, double>{
      for (final entry in byCode.entries)
        if (entry.value.ratePerUsd > 0 && entry.value.ratePerUsd.isFinite)
          entry.key: entry.value.ratePerUsd,
    };
    // USD is the pivot; without it every conversion would report a missing rate.
    table.putIfAbsent('USD', () => 1);
    return RateTable._(table);
  }

  static bool _beats(Rate candidate, Rate incumbent) {
    if (candidate.source != incumbent.source) {
      return candidate.source == RateSource.manual;
    }
    return candidate.updatedAt.isAfter(incumbent.updatedAt);
  }

  /// Rate per USD, or `null` when the code is unknown.
  double? rateFor(String code) => _rates[code.toUpperCase()];

  bool has(String code) => rateFor(code) != null;

  /// Codes from [codes] this table cannot convert.
  Set<String> missing(Iterable<String> codes) => {
    for (final code in codes)
      if (!has(code)) code.toUpperCase(),
  };

  /// Converts [minor] minor units of [from] into minor units of [to].
  ///
  /// Returns `null` when either rate is unknown — the caller must surface that
  /// as a missing rate rather than silently treating the amount as zero.
  int? convertMinor(int minor, {required String from, required String to}) {
    final fromCode = from.toUpperCase();
    final toCode = to.toUpperCase();
    if (fromCode == toCode) return minor;

    final fromRate = rateFor(fromCode);
    final toRate = rateFor(toCode);
    if (fromRate == null || toRate == null) return null;

    // Through USD: `base = amount / r[code] * r[base]`, with the major/minor
    // scaling left to Money so it is defined in exactly one place.
    final major = Money(minor, decimals: Currency.decimalsOf(fromCode)).major;
    final toDecimals = Currency.decimalsOf(toCode);
    final converted = major / fromRate * toRate;

    // A rate can be finite and still produce an unrepresentable amount: a rate
    // of 1e-320 divides into infinity, and one of 1e-300 overflows int64 and
    // would silently saturate. `.round()` throws on the former and lies on the
    // latter, so neither may reach it — an amount this app cannot hold is
    // reported like a missing rate instead.
    final scaled = converted * _pow10(toDecimals);
    if (!scaled.isFinite || scaled.abs() > _maxSafeMinor) return null;

    return Money.fromMajor(converted, decimals: toDecimals).minor;
  }

  /// Largest magnitude `.round()` can turn into an `int` without saturating at
  /// the 64-bit boundary. Any real balance is many orders of magnitude below it.
  static const _maxSafeMinor = 9.0e18;

  static double _pow10(int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}
