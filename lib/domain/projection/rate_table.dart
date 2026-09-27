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
    final table = <String, double>{
      for (final entry in byCode.entries)
        if (entry.value.ratePerUsd > 0) entry.key: entry.value.ratePerUsd,
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
    final converted = major / fromRate * toRate;
    return Money.fromMajor(
      converted,
      decimals: Currency.decimalsOf(toCode),
    ).minor;
  }
}
