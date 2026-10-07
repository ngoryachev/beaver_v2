import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/forecast_horizon.dart';
import '../../domain/models/amount_sort.dart';
import '../../domain/models/user_settings.dart';
import '../../domain/projection/project_balance.dart';
import 'accounts_provider.dart';
import 'repo_providers.dart';

/// The user's settings row, created with defaults the first time it is needed.
class SettingsNotifier extends AsyncNotifier<UserSettings?> {
  @override
  Future<UserSettings?> build() async {
    // Per-user data: see [currentUserIdProvider].
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return null;

    final repository = ref.watch(settingsRepositoryProvider);
    final stored = await repository.get();
    if (stored != null) return stored;
    final fresh = UserSettings(userId: userId, baseCurrency: 'RUB');
    await repository.save(fresh);
    return fresh;
  }

  Future<void> setBaseCurrency(String code) => _update(
    (settings) => settings.copyWith(baseCurrency: code.toUpperCase()),
  );

  Future<void> setForecastHorizon(ForecastHorizon horizon) => _update(
    (settings) => settings.copyWith(
      forecastPreset: horizon.preset,
      // Kept even when another preset is selected, so coming back to «Другая
      // дата» remembers the date instead of asking for it again.
      forecastCustomDate: horizon.customDate,
    ),
  );

  Future<void> setAccountsSort(AmountSort direction) =>
      _update((settings) => settings.copyWith(accountsSort: direction));

  Future<void> setOpsSort(AmountSort direction) =>
      _update((settings) => settings.copyWith(opsSort: direction));

  /// Saves one changed field of the row.
  ///
  /// Always derived from the current value: rebuilding the row from scratch
  /// would reset every setting the caller did not mention — picking a base
  /// currency would throw away the forecast horizon.
  Future<void> _update(UserSettings Function(UserSettings) change) async {
    final current = state.valueOrNull;
    final userId = current?.userId ?? ref.read(currentUserIdProvider);
    if (userId == null) return;
    final base = current ?? UserSettings(userId: userId, baseCurrency: 'RUB');
    await ref.read(settingsRepositoryProvider).save(change(base));
    ref.invalidateSelf();
    await future;
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, UserSettings?>(
  SettingsNotifier.new,
);

/// The currency every total is shown in.
///
/// Invariant: always a currency of some non-archived account. The stored value is
/// normalised on read instead of being rewritten, so archiving the last EUR
/// account moves the total to another currency without an extra database write.
final baseCurrencyProvider = Provider<String>((ref) {
  final stored = ref.watch(settingsProvider).valueOrNull?.baseCurrency ?? 'RUB';
  final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
  return normalizeBaseCurrency(stored, accounts);
});

/// Currencies the user can cycle the total through: those of the live accounts.
final baseCurrencyOptionsProvider = Provider<List<String>>((ref) {
  final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
  return baseCurrencyCandidates(accounts);
});

/// Direction of the by-amount sort of the accounts on the home screen.
final accountsSortProvider = Provider<AmountSort>(
  (ref) =>
      ref.watch(settingsProvider).valueOrNull?.accountsSort ?? AmountSort.desc,
);

/// Direction of the by-amount sort of the operations on the home screen.
final opsSortProvider = Provider<AmountSort>(
  (ref) => ref.watch(settingsProvider).valueOrNull?.opsSort ?? AmountSort.desc,
);
