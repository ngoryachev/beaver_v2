import '../../domain/models/scenario.dart';
import '../../domain/repositories/scenarios_repository.dart';

class InMemoryScenariosRepository implements ScenariosRepository {
  final Map<String, Scenario> _scenarios = {};

  InMemoryScenariosRepository([List<Scenario> seed = const []]) {
    for (final scenario in seed) {
      _scenarios[scenario.id] = scenario;
    }
  }

  @override
  Future<List<Scenario>> getAll() async {
    final all = _scenarios.values.toList()
      ..sort((a, b) {
        // The default scenario always heads the list.
        if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return all;
  }

  @override
  Future<void> save(Scenario scenario) async {
    _scenarios[scenario.id] = scenario;
  }

  @override
  Future<void> delete(String id) async {
    _scenarios.remove(id);
  }
}
