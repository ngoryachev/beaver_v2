import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/planned_op.dart';
import '../../../router.dart';
import '../../format/money_format.dart';
import '../../providers/ops_provider.dart';
import '../../providers/write_guard.dart';
import 'op_labels.dart';

/// Planned operations, grouped by category.
///
/// Grouping beats a flat chronological list here: operations repeat, so "what do
/// I spend on food" is the question this screen answers.
class OpsListScreen extends ConsumerWidget {
  const OpsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opsState = ref.watch(opsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Операции')),
      body: opsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Не удалось загрузить операции: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(opsProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
        data: (ops) => ops.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Пока нет операций. Добавьте регулярный доход или расход, '
                    'чтобы увидеть прогноз.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : _OpsList(ops: ops),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.opEdit),
        tooltip: 'Новая операция',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _OpsList extends ConsumerWidget {
  final List<PlannedOp> ops;

  const _OpsList({required this.ops});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Enum declaration order drives the section order, so it is stable across
    // rebuilds regardless of how the rows came back from the database.
    final grouped = <OpCategory, List<PlannedOp>>{};
    for (final op in ops) {
      grouped.putIfAbsent(op.category, () => []).add(op);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final category in OpCategory.values)
          if (grouped[category] != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Icon(
                    categoryIcon(category),
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    categoryLabel(category),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            for (final op in grouped[category]!) _OpTile(op: op),
          ],
      ],
    );
  }
}

class _OpTile extends ConsumerWidget {
  final PlannedOp op;

  const _OpTile({required this.op});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isIncome = op.kind == OpKind.income;

    return Dismissible(
      key: ValueKey('op-${op.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: theme.colorScheme.errorContainer,
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Удалить операцию?'),
            content: Text(op.title),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return false;
        return runWrite(
          context,
          () => ref.read(opsProvider.notifier).delete(op.id),
          failureMessage: 'Не удалось удалить операцию',
        );
      },
      child: ListTile(
        onTap: () => context.push(Routes.opEdit, extra: op.id),
        title: Text(
          op.title,
          style: TextStyle(
            // A disabled operation is still listed, just visibly inert.
            color: op.enabled ? null : theme.disabledColor,
          ),
        ),
        subtitle: Text(_subtitle()),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${isIncome ? '+' : '−'}'
              '${formatMoney(op.amount, op.currencyCode)}',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: op.enabled
                    ? (isIncome
                          ? Colors.green.shade700
                          : theme.colorScheme.error)
                    : theme.disabledColor,
              ),
            ),
            Switch(
              value: op.enabled,
              onChanged: (enabled) => runWrite(
                context,
                () => ref
                    .read(opsProvider.notifier)
                    .setEnabled(op, enabled: enabled),
                failureMessage: 'Не удалось переключить операцию',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[scheduleLabel(op.schedule)];
    if (op.schedule == Schedule.once) {
      parts.add(formatDate(op.startDate));
    } else {
      parts.add('с ${formatDate(op.startDate)}');
      if (op.endDate != null) parts.add('по ${formatDate(op.endDate!)}');
    }
    return parts.join(' · ');
  }
}
