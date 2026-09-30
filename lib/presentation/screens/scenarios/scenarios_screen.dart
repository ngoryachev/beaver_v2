import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router.dart';
import '../../providers/scenarios_provider.dart';
import '../../providers/write_guard.dart';

/// Picks and manages scenarios. The default «Все» is always present and cannot be
/// deleted, so there is always something to fall back to.
class ScenariosScreen extends ConsumerWidget {
  const ScenariosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenariosState = ref.watch(scenariosProvider);
    final active = ref.watch(activeScenarioProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Сценарии')),
      body: scenariosState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Не удалось загрузить сценарии: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(scenariosProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
        data: (scenarios) => RadioGroup<String>(
          groupValue: active?.id,
          onChanged: (value) =>
              ref.read(activeScenarioIdProvider.notifier).state = value,
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Сценарий выключает часть счетов и операций, не удаляя их. '
                  'Новые счета и операции попадают во все сценарии.',
                ),
              ),
              for (final scenario in scenarios)
                ListTile(
                  leading: Radio<String>(value: scenario.id),
                  title: Text(scenario.name),
                  subtitle: Text(
                    scenario.isDefault
                        ? 'Учитывает всё'
                        : 'Выключено: счетов ${scenario.disabledAccountIds.length}, '
                              'операций ${scenario.disabledOpIds.length}',
                  ),
                  onTap: () =>
                      ref.read(activeScenarioIdProvider.notifier).state =
                          scenario.id,
                  trailing: scenario.isDefault
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Изменить',
                              onPressed: () => context.push(
                                Routes.scenarioEdit,
                                extra: scenario.id,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Удалить',
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('Удалить сценарий?'),
                                    content: Text(scenario.name),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(
                                          dialogContext,
                                        ).pop(false),
                                        child: const Text('Отмена'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.of(
                                          dialogContext,
                                        ).pop(true),
                                        child: const Text('Удалить'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true || !context.mounted) {
                                  return;
                                }
                                await runWrite(
                                  context,
                                  () => ref
                                      .read(scenariosProvider.notifier)
                                      .delete(scenario.id),
                                  failureMessage: 'Не удалось удалить сценарий',
                                );
                              },
                            ),
                          ],
                        ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.scenarioEdit),
        tooltip: 'Новый сценарий',
        child: const Icon(Icons.add),
      ),
    );
  }
}
