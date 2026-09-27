import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/account.dart';
import '../../../domain/models/rate.dart';
import '../../format/money_format.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/auth_providers.dart';
import '../../providers/rate_refresh_provider.dart';
import '../../providers/rates_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/write_guard.dart';

/// Rates, archived accounts and signing out.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final baseCurrency = ref.watch(baseCurrencyProvider);
    final accounts =
        ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final archived = accounts.where((account) => account.archived).toList();
    final refreshState = ref.watch(rateRefreshProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Базовая валюта'),
            subtitle: Text('$baseCurrency · итог считается в ней'),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Курсы к доллару',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (refreshState.isLoading)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Обновить сейчас'),
                    onPressed: () =>
                        ref.read(rateRefreshProvider.notifier).refreshNow(),
                  ),
              ],
            ),
          ),
          if (refreshState.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Не удалось обновить курсы: ${refreshState.error}',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const _RatesTable(),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Архивные счёта', style: theme.textTheme.titleMedium),
          ),
          if (archived.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Архивных счетов нет'),
            )
          else
            for (final account in archived)
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(account.name),
                subtitle: Text(
                  formatMoney(account.balance, account.currencyCode),
                ),
                trailing: TextButton(
                  child: const Text('Вернуть'),
                  onPressed: () => runWrite(
                    context,
                    () => ref
                        .read(accountsProvider.notifier)
                        .setArchived(account, archived: false),
                    failureMessage: 'Не удалось вернуть счёт',
                  ),
                ),
              ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Активные счёта', style: theme.textTheme.titleMedium),
          ),
          for (final account in accounts.where((a) => !a.archived))
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(account.name),
              subtitle: Text(
                formatMoney(account.balance, account.currencyCode),
              ),
              trailing: TextButton(
                child: const Text('В архив'),
                onPressed: () => runWrite(
                  context,
                  () => ref
                      .read(accountsProvider.notifier)
                      .setArchived(account, archived: true),
                  failureMessage: 'Не удалось убрать счёт в архив',
                ),
              ),
            ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              'Выйти',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Выйти из аккаунта?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Отмена'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Выйти'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              await ref.read(authControllerProvider.notifier).signOut();
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// One row per currency in use: the rate, where it came from, and the actions.
///
/// «Сбросить» deletes the row rather than overwriting it, which is what lets the
/// next auto refresh fill it in again.
class _RatesTable extends ConsumerWidget {
  const _RatesTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final codes = ref.watch(usedCurrencyCodesProvider).toList()..sort();
    final rates = ref.watch(ratesProvider).valueOrNull ?? const <Rate>[];
    final byCode = {for (final rate in rates) rate.code.toUpperCase(): rate};

    if (codes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Курсы не нужны: нет счетов и операций'),
      );
    }

    return Column(
      children: [
        for (final code in codes)
          if (code != 'USD')
            ListTile(
              title: Text(code),
              subtitle: Text(_subtitle(byCode[code])),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    child: const Text('Задать'),
                    onPressed: () =>
                        _editRate(context, ref, code, byCode[code]),
                  ),
                  if (byCode[code]?.source == RateSource.manual)
                    TextButton(
                      child: const Text('Сбросить'),
                      onPressed: () => runWrite(
                        context,
                        () => ref.read(ratesProvider.notifier).reset(code),
                        failureMessage: 'Не удалось сбросить курс',
                      ),
                    ),
                ],
              ),
            )
          else
            ListTile(
              title: const Text('USD'),
              subtitle: Text(
                '1 — опорная валюта',
                style: theme.textTheme.bodySmall,
              ),
            ),
      ],
    );
  }

  String _subtitle(Rate? rate) {
    if (rate == null) return 'Нет курса';
    final source = rate.source == RateSource.manual ? 'вручную' : 'авто';
    return '${formatRate(rate.ratePerUsd)} за 1 USD · $source · '
        '${formatDate(rate.updatedAt.toLocal())}';
  }

  Future<void> _editRate(
    BuildContext context,
    WidgetRef ref,
    String code,
    Rate? current,
  ) async {
    final controller = TextEditingController(
      text: current?.ratePerUsd.toString() ?? '',
    );
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Курс $code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Сколько $code за 1 USD',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );
              Navigator.of(
                dialogContext,
              ).pop(parsed != null && parsed > 0 ? parsed : null);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !context.mounted) return;
    await runWrite(
      context,
      () => ref.read(ratesProvider.notifier).setManual(code, value),
      failureMessage: 'Не удалось сохранить курс',
    );
  }
}
