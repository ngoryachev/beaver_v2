import '../models/account.dart';

abstract class AccountsRepository {
  /// Every account of the current user, archived ones included, by sort order.
  Future<List<Account>> getAll();

  Future<void> save(Account account);

  Future<void> delete(String id);

  /// Moves money between two accounts of the same user. Amounts are positive
  /// minor units in each account's own currency, so a cross-currency transfer
  /// carries its own rate.
  Future<void> transfer({
    required String fromAccountId,
    required String toAccountId,
    required int fromAmount,
    required int toAmount,
  });
}
