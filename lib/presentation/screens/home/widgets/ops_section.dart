import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/planned_op.dart';
import '../../../../domain/projection/monthly_equivalent.dart';
import '../../../../domain/projection/rate_table.dart';
import '../../../../router.dart';
import '../../../format/money_format.dart';
import '../../../providers/ops_provider.dart';
import '../../../providers/rates_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/write_guard.dart';
import '../../ops/op_labels.dart';

/// Planned operations on the home screen, grouped by category.
///
/// Grouping beats a flat chronological list here: operations repeat, so "what do
/// I spend on food" is the question this section answers. Groups start collapsed
/// and each header carries its own monthly estimate, so the whole section is a
/// budget summary until the user opens a category.
///
/// The expanded set belongs to the home screen rather than to this widget: it is
/// rebuilt whenever accounts or rates change, and local state here would be
/// thrown away with it.
class OpsSection extends ConsumerWidget {
  final Set<OpCategory> expanded;
  final ValueChanged<OpCategory> onToggle;

  const OpsSection({
    super.key,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final opsState = ref.watch(opsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Операции', style: theme.textTheme.titleMedium),
        ),
        opsState.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          // Inline, not a full-screen error: the accounts above loaded fine and
          // the total is still worth showing.
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
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
          data: (ops) => ops.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Пока нет операций. Добавьте регулярный доход или расход, '
                    'чтобы увидеть прогноз.',
                    textAlign: TextAlign.center,
                  ),
                )
              : _Groups(ops: ops, expanded: expanded, onToggle: onToggle),
        ),
      ],
    );
  }
}

class _Groups extends ConsumerWidget {
  final List<PlannedOp> ops;
  final Set<OpCategory> expanded;
  final ValueChanged<OpCategory> onToggle;

  const _Groups({
    required this.ops,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseCurrency = ref.watch(baseCurrencyProvider);
    final rates = ref.watch(rateTableProvider);

    // Enum declaration order drives the section order, so it is stable across
    // rebuilds regardless of how the rows came back from the database.
    final grouped = <OpCategory, List<PlannedOp>>{};
    for (final op in ops) {
      grouped.putIfAbsent(op.category, () => []).add(op);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final category in OpCategory.values)
          if (grouped[category] != null) ...[
            _GroupHeader(
              category: category,
              ops: grouped[category]!,
              expanded: expanded.contains(category),
              onToggle: () => onToggle(category),
              rates: rates,
              baseCurrency: baseCurrency,
            ),
            if (expanded.contains(category))
              for (final op in grouped[category]!)
                _OpTile(op: op, rates: rates, baseCurrency: baseCurrency),
          ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final OpCategory category;
  final List<PlannedOp> ops;
  final bool expanded;
  final VoidCallback onToggle;
  final RateTable rates;
  final String baseCurrency;

  const _GroupHeader({
    required this.category,
    required this.ops,
    required this.expanded,
    required this.onToggle,
    required this.rates,
    required this.baseCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(
          children: [
            Icon(
              categoryIcon(category),
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                categoryLabel(category),
                // «Коммунальные платежи» next to an estimate is wider than a
                // phone: the label is what gives way, not the figure.
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            // Only while collapsed: with the operations in view their own
            // amounts say it better than an average does.
            if (!expanded)
              Text(
                _monthlyLabel(),
                softWrap: false,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.right,
              ),
            Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20),
          ],
        ),
      ),
    );
  }

  /// «−42 000 ₽ / мес»: every operation of the group brought to a monthly
  /// equivalent and summed with its sign. Kopecks are dropped — an estimate
  /// built from "4.35 weeks a month" has no business showing them.
  String _monthlyLabel() {
    final total = monthlyTotal(
      ops: ops,
      rates: rates,
      baseCurrency: baseCurrency,
      today: DateTime.now(),
    );
    final sign = total.amountMinor > 0
        ? '+'
        : total.amountMinor < 0
        ? '−'
        : '';
    final amount = formatMoneyCompact(total.amountMinor.abs(), baseCurrency);
    final suffix = total.partial ? ' · нет курса' : '';
    return '$sign$amount / мес$suffix';
  }
}

class _OpTile extends ConsumerWidget {
  final PlannedOp op;
  final RateTable rates;
  final String baseCurrency;

  const _OpTile({
    required this.op,
    required this.rates,
    required this.baseCurrency,
  });

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
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
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
                if (_baseNote() case final note?)
                  Text(note, style: theme.textTheme.bodySmall),
              ],
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

  /// The amount in the base currency, when the operation is in another one.
  ///
  /// Same three cases as `AccountCard` and the forecast's event list: the
  /// converted amount, a rate the user can go and set, or an amount too large to
  /// express — saying «Нет курса» for the last would send them to fix something
  /// that is not broken.
  String? _baseNote() {
    if (op.currencyCode.toUpperCase() == baseCurrency.toUpperCase()) {
      return null;
    }
    final converted = rates.convertMinor(
      op.amount,
      from: op.currencyCode,
      to: baseCurrency,
    );
    if (converted != null) return '≈ ${formatMoney(converted, baseCurrency)}';
    return rates.has(op.currencyCode) && rates.has(baseCurrency)
        ? 'Слишком большая сумма'
        : 'Нет курса ${op.currencyCode.toUpperCase()}';
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
