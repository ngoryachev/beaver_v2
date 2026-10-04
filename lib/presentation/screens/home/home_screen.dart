import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/account.dart';
import '../../../domain/models/planned_op.dart';
import '../../../router.dart';
import '../../format/money_format.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/forecast_horizon_provider.dart';
import '../../providers/projection_provider.dart';
import '../../providers/rates_provider.dart';
import '../../providers/scenarios_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/write_guard.dart';
import 'balance_edit_sheet.dart';
import 'transfer_sheet.dart';
import 'widgets/account_card.dart';
import 'widgets/add_account_dialog.dart';
import 'widgets/ops_section.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsState = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beaver'),
        actions: [
          IconButton(
            icon: const Icon(Icons.show_chart),
            tooltip: 'Прогноз',
            onPressed: () => context.push(Routes.forecast),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Настройки',
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: accountsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorBody(
          error: error,
          onRetry: () => ref.invalidate(accountsProvider),
        ),
        data: (accounts) => _HomeBody(accounts: accounts),
      ),
      floatingActionButton: const _HomeFab(),
    );
  }
}

class _HomeBody extends ConsumerStatefulWidget {
  final List<Account> accounts;

  const _HomeBody({required this.accounts});

  @override
  ConsumerState<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends ConsumerState<_HomeBody> {
  /// Categories the user has opened. Empty — everything collapsed — is the
  /// default: the section then reads as a per-category budget rather than as a
  /// long list the accounts above have to scroll past.
  final _expanded = <OpCategory>{};

  @override
  Widget build(BuildContext context) {
    final live = widget.accounts
        .where((account) => !account.archived)
        .toList();
    final baseCurrency = ref.watch(baseCurrencyProvider);
    final rates = ref.watch(rateTableProvider);
    final scenario = ref.watch(activeScenarioProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(accountsProvider);
        ref.invalidate(ratesProvider);
        await ref.read(accountsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const _TotalCard(),
          if (scenario != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.alt_route, size: 18),
                  label: Text(scenario.name),
                  onPressed: () => context.push(Routes.scenarios),
                ),
              ),
            ),
          const SizedBox(height: 8),
          const _ForecastPreviewCard(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Счета',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (live.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Пока нет счетов. Добавьте первый, чтобы увидеть итог и прогноз.',
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final account in live)
              _DismissibleAccount(
                account: account,
                child: AccountCard(
                  account: account,
                  baseCurrency: baseCurrency,
                  baseAmount: rates.convertMinor(
                    account.balance,
                    from: account.currencyCode,
                    to: baseCurrency,
                  ),
                  rateKnown:
                      rates.has(account.currencyCode) &&
                      rates.has(baseCurrency),
                  // The total above is scenario-filtered; marking the accounts
                  // it leaves out is what keeps the two from silently
                  // disagreeing.
                  excluded:
                      scenario != null && !scenario.allowsAccount(account.id),
                  onTap: () => BalanceEditSheet.show(context, account),
                ),
              ),
          OpsSection(
            expanded: _expanded,
            onToggle: (category) => setState(
              () => _expanded.contains(category)
                  ? _expanded.remove(category)
                  : _expanded.add(category),
            ),
          ),
        ],
      ),
    );
  }
}

/// Swipe left on an account card to delete it, with a dialog first.
///
/// Deleting is deliberately harder to reach than archiving (one tap in
/// settings): the balance goes with the account, and the planned operations
/// pointing at it are detached by `ON DELETE SET NULL` rather than removed.
class _DismissibleAccount extends ConsumerWidget {
  final Account account;
  final Widget child;

  const _DismissibleAccount({required this.account, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey('account-${account.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
            title: const Text('Удалить счёт?'),
            content: Text(
              '${account.name} · '
              '${formatMoney(account.balance, account.currencyCode)}\n\n'
              'Остаток исчезнет из итога. Привязанные операции останутся, '
              'но потеряют привязку и станут «Любой счёт».',
            ),
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
          () => ref.read(accountsProvider.notifier).delete(account.id),
          failureMessage: 'Не удалось удалить счёт',
        );
      },
      child: child,
    );
  }
}

/// The headline total. Tapping it cycles the base currency through the currencies
/// of the existing accounts — the fastest way to ask "and how much is that in
/// euro?" without opening settings.
class _TotalCard extends ConsumerWidget {
  const _TotalCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final baseCurrency = ref.watch(baseCurrencyProvider);
    final options = ref.watch(baseCurrencyOptionsProvider);
    final projection = ref.watch(currentTotalProvider);
    final canCycle = options.length > 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        color: theme.colorScheme.primaryContainer,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: canCycle ? () => _cycleCurrency(context, ref, options) : null,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Всего',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const Spacer(),
                    if (canCycle)
                      Icon(
                        Icons.swap_horiz,
                        size: 18,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  formatMoney(projection.startBalance, baseCurrency),
                  key: const Key('home-total'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (projection.missingRateCodes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Без курса: ${projection.missingRateCodes.join(', ')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                // Separate line: a rate *is* set for these, so «Без курса»
                // would send the user to fix something that is not broken.
                if (projection.unconvertibleCodes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Слишком большая сумма: '
                    '${projection.unconvertibleCodes.join(', ')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cycleCurrency(
    BuildContext context,
    WidgetRef ref,
    List<String> options,
  ) async {
    final current = ref.read(baseCurrencyProvider);
    final index = options.indexOf(current);
    final next = options[(index + 1) % options.length];
    await runWrite(
      context,
      () => ref.read(settingsProvider.notifier).setBaseCurrency(next),
      failureMessage: 'Не удалось сменить валюту итога',
    );
  }
}

/// The one forecast number worth having on the home screen, plus a warning when
/// the balance dips below zero before then.
///
/// The horizon is whatever was last chosen on the forecast screen — the title
/// names it, so the figure can never be read against the wrong date.
class _ForecastPreviewCard extends ConsumerWidget {
  const _ForecastPreviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final baseCurrency = ref.watch(baseCurrencyProvider);
    final horizon = ref.watch(forecastHorizonProvider);
    final projection = ref.watch(
      projectionProvider(ref.watch(forecastTargetDateProvider)),
    );
    final goesNegative = projection.minBalance < 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push(Routes.forecast),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  goesNegative ? Icons.warning_amber : Icons.trending_up,
                  color: goesNegative ? theme.colorScheme.error : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        horizonLabel(horizon),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatMoney(projection.endBalance, baseCurrency),
                        key: const Key('home-forecast-30'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: projection.endBalance < 0
                              ? theme.colorScheme.error
                              : null,
                        ),
                      ),
                      if (goesNegative)
                        Text(
                          'Минимум ${formatMoney(projection.minBalance, baseCurrency)} '
                          '· ${formatDate(projection.minDate)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Expanding FAB: «Перевод», «Операция», «Счёт».
class _HomeFab extends ConsumerStatefulWidget {
  const _HomeFab();

  @override
  ConsumerState<_HomeFab> createState() => _HomeFabState();
}

class _HomeFabState extends ConsumerState<_HomeFab> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_open) ...[
          _action(
            label: 'Счёт',
            icon: Icons.account_balance_wallet_outlined,
            onPressed: () => AddAccountDialog.show(context),
          ),
          const SizedBox(height: 8),
          _action(
            label: 'Операция',
            icon: Icons.repeat,
            onPressed: () => context.push(Routes.opEdit),
          ),
          const SizedBox(height: 8),
          _action(
            label: 'Перевод',
            icon: Icons.swap_horiz,
            onPressed: () => TransferSheet.show(context),
          ),
          const SizedBox(height: 12),
        ],
        FloatingActionButton(
          onPressed: () => setState(() => _open = !_open),
          tooltip: _open ? 'Закрыть' : 'Добавить',
          child: Icon(_open ? Icons.close : Icons.add),
        ),
      ],
    );
  }

  Widget _action({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return FloatingActionButton.extended(
      heroTag: label,
      onPressed: () {
        setState(() => _open = false);
        onPressed();
      },
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorBody({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Не удалось загрузить данные',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}
