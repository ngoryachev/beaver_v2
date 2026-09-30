import '../../domain/models/account.dart';
import '../../domain/repositories/accounts_repository.dart';

/// Test double for [AccountsRepository]. Supabase itself is never mocked; tests
/// swap the whole repository instead.
class InMemoryAccountsRepository implements AccountsRepository {
  final Map<String, Account> _accounts = {};

  InMemoryAccountsRepository([List<Account> seed = const []]) {
    for (final account in seed) {
      _accounts[account.id] = account;
    }
  }

  @override
  Future<List<Account>> getAll() async {
    final all = _accounts.values.toList()
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
      });
    return all;
  }

  @override
  Future<void> save(Account account) async {
    _accounts[account.id] = account;
  }

  @override
  Future<void> delete(String id) async {
    _accounts.remove(id);
  }

  @override
  Future<void> transfer({
    required String fromAccountId,
    required String toAccountId,
    required int fromAmount,
    required int toAmount,
  }) async {
    final from = _accounts[fromAccountId];
    final to = _accounts[toAccountId];
    if (from == null || to == null) {
      throw StateError('Счёт для перевода не найден');
    }
    _accounts[fromAccountId] = from.copyWith(
      balance: from.balance - fromAmount,
    );
    _accounts[toAccountId] = to.copyWith(balance: to.balance + toAmount);
  }
}
