import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/scenario.dart';
import 'repo_providers.dart';

const _uuid = Uuid();

/// Name of the built-in scenario that excludes nothing.
const defaultScenarioName = 'Все';

/// The user's scenarios, the default one first.
///
/// The default scenario is created on demand: a fresh account has no rows, and
/// the app must still have something to show in the scenario chip.
class ScenariosNotifier extends AsyncNotifier<List<Scenario>> {
  @override
  Future<List<Scenario>> build() async {
    // Per-user data: see [currentUserIdProvider].
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const [];

    final repository = ref.watch(scenariosRepositoryProvider);
    final scenarios = await repository.getAll();
    if (scenarios.any((scenario) => scenario.isDefault)) return scenarios;

    final fallback = Scenario(
      id: _uuid.v4(),
      userId: userId,
      name: defaultScenarioName,
      isDefault: true,
    );
    await repository.save(fallback);
    return repository.getAll();
  }

  Future<void> add(String name) async {
    final userId = ref.read(currentUserIdProvider);
    final scenario = Scenario(
      id: _uuid.v4(),
      userId: userId ?? '',
      name: name.trim(),
    );
    await ref.read(scenariosRepositoryProvider).save(scenario);
    ref.invalidateSelf();
    await future;
  }

  Future<void> save(Scenario scenario) async {
    await ref.read(scenariosRepositoryProvider).save(scenario);
    ref.invalidateSelf();
    await future;
  }

  /// Deleting the default scenario would leave the app with nothing to fall back
  /// on, so it is refused here rather than only hidden in the UI.
  Future<void> delete(String id) async {
    final scenarios = state.valueOrNull ?? const <Scenario>[];
    final target = scenarios.where((scenario) => scenario.id == id).firstOrNull;
    if (target != null && target.isDefault) {
      throw StateError('Сценарий «$defaultScenarioName» нельзя удалить');
    }
    await ref.read(scenariosRepositoryProvider).delete(id);
    if (ref.read(activeScenarioIdProvider) == id) {
      ref.read(activeScenarioIdProvider.notifier).state = null;
    }
    ref.invalidateSelf();
    await future;
  }
}

final scenariosProvider =
    AsyncNotifierProvider<ScenariosNotifier, List<Scenario>>(
      ScenariosNotifier.new,
    );

/// Which scenario the user is looking at. `null` means "the default one", so the
/// selection survives the scenario list loading in.
final activeScenarioIdProvider = StateProvider<String?>((ref) => null);

/// The active scenario, falling back to the default. `null` only while the list
/// is still loading.
final activeScenarioProvider = Provider<Scenario?>((ref) {
  final scenarios = ref.watch(scenariosProvider).valueOrNull;
  if (scenarios == null || scenarios.isEmpty) return null;

  final selectedId = ref.watch(activeScenarioIdProvider);
  if (selectedId != null) {
    final selected = scenarios
        .where((scenario) => scenario.id == selectedId)
        .firstOrNull;
    if (selected != null) return selected;
  }
  return scenarios.where((scenario) => scenario.isDefault).firstOrNull ??
      scenarios.first;
});
