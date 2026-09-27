import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/account.dart';
import '../../domain/repositories/accounts_repository.dart';

class SupabaseAccountsRepository implements AccountsRepository {
  final SupabaseClient _client;

  SupabaseAccountsRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;

  @override
  Future<List<Account>> getAll() async {
    final response = await _client
        .from('accounts')
        .select()
        .eq('user_id', _userId)
        .order('sort_order')
        .order('created_at');

    return response.map(_toEntity).toList();
  }

  @override
  Future<void> save(Account account) async {
    await _client.from('accounts').upsert(_toRow(account));
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('accounts').delete().eq('id', id).eq('user_id', _userId);
  }

  @override
  Future<void> transfer({
    required String fromAccountId,
    required String toAccountId,
    required int fromAmount,
    required int toAmount,
  }) async {
    // Both updates must land together, so the arithmetic happens in the database
    // rather than as two round trips that could half-fail.
    await _client.rpc(
      'transfer',
      params: {
        'from_id': fromAccountId,
        'to_id': toAccountId,
        'from_amount': fromAmount,
        'to_amount': toAmount,
      },
    );
  }

  Map<String, dynamic> _toRow(Account account) => {
    'id': account.id,
    'user_id': _userId,
    'name': account.name,
    'currency_code': account.currencyCode.toUpperCase(),
    'balance': account.balance,
    'archived': account.archived,
    'sort_order': account.sortOrder,
  };

  Account _toEntity(Map<String, dynamic> json) => Account(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    name: json['name'] as String,
    currencyCode: json['currency_code'] as String,
    balance: (json['balance'] as num?)?.toInt() ?? 0,
    archived: json['archived'] as bool? ?? false,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
  );
}
