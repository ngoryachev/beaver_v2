/// Where a rate came from. A `manual` row wins over an `auto` one for the same
/// code, and the auto refresh never overwrites it — resetting a manual rate
/// means deleting the row.
enum RateSource {
  auto('auto'),
  manual('manual');

  final String wire;
  const RateSource(this.wire);

  static RateSource fromWire(String value) =>
      RateSource.values.firstWhere((source) => source.wire == value);
}

/// How many units of [code] one USD buys. USD itself is stored (or implied) as 1.
///
/// Rates are the only place a `double` is allowed; money stays integral.
class Rate {
  final String userId;
  final String code;
  final double ratePerUsd;
  final RateSource source;
  final DateTime updatedAt;

  const Rate({
    required this.userId,
    required this.code,
    required this.ratePerUsd,
    required this.source,
    required this.updatedAt,
  });

  Rate copyWith({
    double? ratePerUsd,
    RateSource? source,
    DateTime? updatedAt,
  }) => Rate(
    userId: userId,
    code: code,
    ratePerUsd: ratePerUsd ?? this.ratePerUsd,
    source: source ?? this.source,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Rate &&
      other.userId == userId &&
      other.code == code &&
      other.ratePerUsd == ratePerUsd &&
      other.source == source &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(userId, code, ratePerUsd, source, updatedAt);
}
