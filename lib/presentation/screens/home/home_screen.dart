import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/account.dart';
import '../../../domain/projection/occurrences.dart';
import '../../../router.dart';
import '../../format/money_format.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/projection_provider.dart';
import '../../providers/rates_provider.dart';
import '../../providers/scenarios_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/write_guard.dart';
import 'balance_edit_sheet.dart';
import 'transfer_sheet.dart';
import 'widgets/account_card.dart';
import 'widgets/add_account_dialog.dart';

/// How far ahead the home screen's forecast widget looks, in calendar days.
const homeForecastDays = 30;

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
            icon: const Icon(Icons.repeat),
            tooltip: 'Операции',
            onPressed: () => context.push(Routes.ops),
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

class _HomeBody extends ConsumerWidget {
  final List<Account> accounts;

  const _HomeBody({required this.accounts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = accounts.where((account) => !account.archived).toList();
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
              'Счёта',
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
              AccountCard(
                account: account,
                baseCurrency: baseCurrency,
                baseAmount: rates.convertMinor(
                  account.balance,
                  from: account.currencyCode,
                  to: baseCurrency,
                ),
                onTap: () => BalanceEditSheet.show(context, account),
              ),
        ],
      ),
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

/// "In 30 days" — the one number that makes the forecast worth having on the home
/// screen, plus a warning when the balance dips below zero before then.
class _ForecastPreviewCard extends ConsumerWidget {
  const _ForecastPreviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final baseCurrency = ref.watch(baseCurrencyProvider);
    // Keyed by a calendar date, not a timestamp: `projectionProvider` is a
    // family whose cache is keyed by the argument, so a raw `DateTime.now()`
    // would leave one dead projection behind on every rebuild. Calendar
    // arithmetic, so the horizon is still 30 days across a DST transition.
    final target = addDays(dateOnly(DateTime.now()), homeForecastDays);
    final projection = ref.watch(projectionProvider(target));
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
                      Text('Через 30 дней', style: theme.textTheme.titleSmall),
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
