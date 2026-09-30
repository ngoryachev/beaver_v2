import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/user_settings.dart';
import '../../domain/repositories/settings_repository.dart';

class SupabaseSettingsRepository implements SettingsRepository {
  final SupabaseClient _client;

  SupabaseSettingsRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;

  @override
  Future<UserSettings?> get() async {
    final row = await _client
        .from('user_settings')
        .select()
        .eq('user_id', _userId)
        .maybeSingle();
    if (row == null) return null;
    return _toEntity(row);
  }

  @override
  Future<void> save(UserSettings settings) async {
    await _client.from('user_settings').upsert(_toRow(settings));
  }

  Map<String, dynamic> _toRow(UserSettings settings) => {
    'user_id': _userId,
    'base_currency': settings.baseCurrency.toUpperCase(),
  };

  UserSettings _toEntity(Map<String, dynamic> json) => UserSettings(
    userId: json['user_id'] as String,
    baseCurrency: json['base_currency'] as String,
  );
}
