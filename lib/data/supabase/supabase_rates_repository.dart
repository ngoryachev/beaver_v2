import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/rate.dart';
import '../../domain/repositories/rates_repository.dart';

class SupabaseRatesRepository implements RatesRepository {
  final SupabaseClient _client;

  SupabaseRatesRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;

  @override
  Future<List<Rate>> getAll() async {
    final response = await _client
        .from('rates')
        .select()
        .eq('user_id', _userId)
        .order('code');

    return response.map(_toEntity).toList();
  }

  @override
  Future<void> upsertAll(List<Rate> rates) async {
    if (rates.isEmpty) return;
    // `(user_id, code)` is unique, so the conflict target is what lets an auto
    // refresh update an existing row instead of failing on the constraint.
    await _client
        .from('rates')
        .upsert(rates.map(_toRow).toList(), onConflict: 'user_id,code');
  }

  @override
  Future<void> delete(String code) async {
    await _client
        .from('rates')
        .delete()
        .eq('user_id', _userId)
        .eq('code', code.toUpperCase());
  }

  Map<String, dynamic> _toRow(Rate rate) => {
    'user_id': _userId,
    'code': rate.code.toUpperCase(),
    'rate_per_usd': rate.ratePerUsd,
    'source': rate.source.wire,
    'updated_at': rate.updatedAt.toUtc().toIso8601String(),
  };

  Rate _toEntity(Map<String, dynamic> json) => Rate(
    userId: json['user_id'] as String,
    code: json['code'] as String,
    ratePerUsd: (json['rate_per_usd'] as num).toDouble(),
    source: RateSource.fromWire(json['source'] as String? ?? 'auto'),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );
}
