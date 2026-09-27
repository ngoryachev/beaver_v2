import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<void> setBaseCurrency(String code) async {
    final current = state.valueOrNull;
    final userId = current?.userId ?? ref.read(currentUserIdProvider);
    if (userId == null) return;
    await ref
        .read(settingsRepositoryProvider)
        .save(UserSettings(userId: userId, baseCurrency: code.toUpperCase()));
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
