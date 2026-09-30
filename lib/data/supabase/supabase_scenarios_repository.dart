import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/scenario.dart';
import '../../domain/repositories/scenarios_repository.dart';

class SupabaseScenariosRepository implements ScenariosRepository {
  final SupabaseClient _client;

  SupabaseScenariosRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;

  @override
  Future<List<Scenario>> getAll() async {
    final response = await _client
        .from('scenarios')
        .select()
        .eq('user_id', _userId)
        // Default first, then creation order, matching how the picker lists them.
        .order('is_default', ascending: false)
        .order('created_at');

    return response.map(_toEntity).toList();
  }

  @override
  Future<void> save(Scenario scenario) async {
    await _client.from('scenarios').upsert(_toRow(scenario));
  }

  @override
  Future<void> delete(String id) async {
    await _client
        .from('scenarios')
        .delete()
        .eq('id', id)
        .eq('user_id', _userId);
  }

  Map<String, dynamic> _toRow(Scenario scenario) => {
    'id': scenario.id,
    'user_id': _userId,
    'name': scenario.name,
    'is_default': scenario.isDefault,
    'disabled_account_ids': scenario.disabledAccountIds.toList(),
    'disabled_op_ids': scenario.disabledOpIds.toList(),
  };

  Scenario _toEntity(Map<String, dynamic> json) => Scenario(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    name: json['name'] as String,
    isDefault: json['is_default'] as bool? ?? false,
    disabledAccountIds: _toIdSet(json['disabled_account_ids']),
    disabledOpIds: _toIdSet(json['disabled_op_ids']),
  );

  Set<String> _toIdSet(Object? value) =>
      value is List ? {for (final id in value) id as String} : const <String>{};
}
