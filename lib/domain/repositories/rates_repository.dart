import '../models/rate.dart';

/// One row per currency code (`unique (user_id, code)`); [Rate.source] records
/// whether the value came from the rate API or from the user.
abstract class RatesRepository {
  Future<List<Rate>> getAll();

  /// Writes [rates] as-is. The auto refresh must filter out codes that already
  /// have a `manual` row, so a user override is never clobbered.
  Future<void> upsertAll(List<Rate> rates);

  /// Drops the row for [code]. This is how a manual rate is "reset": once the
  /// row is gone the next auto refresh fills it in again.
  Future<void> delete(String code);
}
