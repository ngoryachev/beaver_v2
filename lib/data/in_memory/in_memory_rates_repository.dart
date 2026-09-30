import '../../domain/models/rate.dart';
import '../../domain/repositories/rates_repository.dart';

/// Mirrors the `unique (user_id, code)` constraint: one row per currency, whose
/// `source` says whether it came from the API or the user.
class InMemoryRatesRepository implements RatesRepository {
  final Map<String, Rate> _rates = {};

  InMemoryRatesRepository([List<Rate> seed = const []]) {
    for (final rate in seed) {
      _rates[rate.code.toUpperCase()] = rate;
    }
  }

  @override
  Future<List<Rate>> getAll() async => _rates.values.toList();

  @override
  Future<void> upsertAll(List<Rate> rates) async {
    for (final rate in rates) {
      _rates[rate.code.toUpperCase()] = rate;
    }
  }

  @override
  Future<void> delete(String code) async {
    _rates.remove(code.toUpperCase());
  }
}
