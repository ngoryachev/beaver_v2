import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/rate.dart';
import '../../domain/projection/rate_table.dart';
import 'accounts_provider.dart';
import 'ops_provider.dart';
import 'repo_providers.dart';

/// Stored exchange rates, one row per currency.
class RatesNotifier extends AsyncNotifier<List<Rate>> {
  @override
  Future<List<Rate>> build() {
    return ref.watch(ratesRepositoryProvider).getAll();
  }

  /// Stores a rate the user typed. Marked `manual`, so the auto refresh will skip
  /// this code from now on.
  Future<void> setManual(String code, double ratePerUsd) async {
    final userId = ref.read(currentUserIdProvider);
    await ref.read(ratesRepositoryProvider).upsertAll([
      Rate(
        userId: userId ?? '',
        code: code.toUpperCase(),
        ratePerUsd: ratePerUsd,
        source: RateSource.manual,
        updatedAt: DateTime.now().toUtc(),
      ),
    ]);
    ref.invalidateSelf();
    await future;
  }

  /// Drops the row so the next auto refresh can recreate it — this is what
  /// "сбросить" does to a manual override.
  Future<void> reset(String code) async {
    await ref.read(ratesRepositoryProvider).delete(code);
    ref.invalidateSelf();
    await future;
  }

  /// Writes freshly fetched rates. Codes with a manual row are filtered out, so a
  /// user override is never clobbered.
  Future<void> applyAuto(Map<String, double> fetched) async {
    if (fetched.isEmpty) return;
    final userId = ref.read(currentUserIdProvider);
    final manualCodes = {
      for (final rate in state.valueOrNull ?? const <Rate>[])
        if (rate.source == RateSource.manual) rate.code.toUpperCase(),
    };
    final now = DateTime.now().toUtc();
    final rows = <Rate>[
      for (final entry in fetched.entries)
        if (!manualCodes.contains(entry.key.toUpperCase()))
          Rate(
            userId: userId ?? '',
            code: entry.key.toUpperCase(),
            ratePerUsd: entry.value,
            source: RateSource.auto,
            updatedAt: now,
          ),
    ];
    if (rows.isEmpty) return;
    await ref.read(ratesRepositoryProvider).upsertAll(rows);
    ref.invalidateSelf();
    await future;
  }
}

final ratesProvider = AsyncNotifierProvider<RatesNotifier, List<Rate>>(
  RatesNotifier.new,
);

/// Conversion table built from the stored rates.
final rateTableProvider = Provider<RateTable>((ref) {
  final rates = ref.watch(ratesProvider).valueOrNull ?? const <Rate>[];
  return RateTable.fromRates(rates);
});

/// Every currency code the app needs a rate for: those of the accounts and of the
/// planned operations. Nothing else is worth fetching or storing.
final usedCurrencyCodesProvider = Provider<Set<String>>((ref) {
  final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
  final ops = ref.watch(opsProvider).valueOrNull ?? const [];
  return {
    for (final account in accounts) account.currencyCode.toUpperCase(),
    for (final op in ops) op.currencyCode.toUpperCase(),
  };
});

/// Timestamp of the freshest `auto` row, or `null` when there is none.
final latestAutoRateAtProvider = Provider<DateTime?>((ref) {
  final rates = ref.watch(ratesProvider).valueOrNull ?? const <Rate>[];
  DateTime? latest;
  for (final rate in rates) {
    if (rate.source != RateSource.auto) continue;
    if (latest == null || rate.updatedAt.isAfter(latest)) {
      latest = rate.updatedAt;
    }
  }
  return latest;
});
