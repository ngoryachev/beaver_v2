/// Postgres `DATE` columns carry no time zone, so the client must not let
/// `toIso8601String()` shift a date across midnight. These two helpers are the
/// only place a date crosses the wire.
String dateToWire(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Parses `YYYY-MM-DD` (or a full timestamp) into local midnight.
DateTime dateFromWire(String value) {
  final parsed = DateTime.parse(value);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// Reads a `rate_per_usd` value off the wire.
///
/// The column is `DOUBLE PRECISION`, and Postgres accepts `Infinity` and `NaN`
/// there — `CHECK (rate_per_usd > 0)` does not exclude them. PostgREST
/// serialises those as JSON *strings*, which a plain `as num` cast throws on,
/// failing the whole query and wiping every rate from the app.
///
/// Such a row is unusable — `RateTable` drops non-finite rates — but it still
/// has to load, so settings can list it and «Сбросить» can delete it. Anything
/// unrecognisable becomes NaN and is dropped the same way.
double rateFromWire(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? double.nan;
  return double.nan;
}
