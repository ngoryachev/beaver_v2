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
