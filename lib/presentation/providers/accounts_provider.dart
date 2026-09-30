import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/account.dart';
import 'repo_providers.dart';

const _uuid = Uuid();

/// The user's accounts, archived ones included.
///
/// Writes are pessimistic: the repository call happens first and the list is then
/// invalidated, so the UI only ever shows what the database actually accepted.
class AccountsNotifier extends AsyncNotifier<List<Account>> {
  @override
  Future<List<Account>> build() {
    // Per-user data: see [currentUserIdProvider].
    if (ref.watch(currentUserIdProvider) == null) {
      return Future.value(const <Account>[]);
    }
    return ref.watch(accountsRepositoryProvider).getAll();
  }

  Future<void> add({
    required String name,
    required String currencyCode,
    int balance = 0,
  }) async {
    final userId = ref.read(currentUserIdProvider);
    final existing = state.valueOrNull ?? const <Account>[];
    final account = Account(
      // Generated client-side so the row can be referenced before the round trip.
      id: _uuid.v4(),
      userId: userId ?? '',
      name: name.trim(),
      currencyCode: currencyCode.toUpperCase(),
      balance: balance,
      sortOrder: existing.isEmpty
          ? 0
          : existing.map((a) => a.sortOrder).reduce((a, b) => a > b ? a : b) +
                1,
    );
    await ref.read(accountsRepositoryProvider).save(account);
    ref.invalidateSelf();
    await future;
  }

  Future<void> save(Account account) async {
    await ref.read(accountsRepositoryProvider).save(account);
    ref.invalidateSelf();
    await future;
  }

  /// Replaces the balance outright — this is the only path that changes it apart
  /// from [transfer]. Planned operations never do.
  Future<void> setBalance(Account account, int balance) =>
      save(account.copyWith(balance: balance));

  Future<void> setArchived(Account account, {required bool archived}) =>
      save(account.copyWith(archived: archived));

  Future<void> delete(String id) async {
    await ref.read(accountsRepositoryProvider).delete(id);
    ref.invalidateSelf();
    await future;
  }

  Future<void> transfer({
    required String fromAccountId,
    required String toAccountId,
    required int fromAmount,
    required int toAmount,
  }) async {
    await ref
        .read(accountsRepositoryProvider)
        .transfer(
          fromAccountId: fromAccountId,
          toAccountId: toAccountId,
          fromAmount: fromAmount,
          toAmount: toAmount,
        );
    ref.invalidateSelf();
    await future;
  }
}

final accountsProvider = AsyncNotifierProvider<AccountsNotifier, List<Account>>(
  AccountsNotifier.new,
);

/// Non-archived accounts only — what the home screen and forecast use.
final activeAccountsProvider = Provider<List<Account>>((ref) {
  final accounts = ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
  return accounts.where((account) => !account.archived).toList();
});
