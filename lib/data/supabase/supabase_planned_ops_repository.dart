import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/planned_op.dart';
import '../../domain/repositories/planned_ops_repository.dart';
import 'date_wire.dart';

class SupabasePlannedOpsRepository implements PlannedOpsRepository {
  final SupabaseClient _client;

  SupabasePlannedOpsRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;

  @override
  Future<List<PlannedOp>> getAll() async {
    final response = await _client
        .from('planned_ops')
        .select()
        .eq('user_id', _userId)
        .order('created_at');

    return response.map(_toEntity).toList();
  }

  @override
  Future<void> save(PlannedOp op) async {
    await _client.from('planned_ops').upsert(_toRow(op));
  }

  @override
  Future<void> delete(String id) async {
    await _client
        .from('planned_ops')
        .delete()
        .eq('id', id)
        .eq('user_id', _userId);
  }

  Map<String, dynamic> _toRow(PlannedOp op) => {
    'id': op.id,
    'user_id': _userId,
    'title': op.title,
    'amount': op.amount,
    'currency_code': op.currencyCode.toUpperCase(),
    'kind': op.kind.wire,
    'category': op.category.wire,
    'account_id': op.accountId,
    'schedule': op.schedule.wire,
    'start_date': dateToWire(op.startDate),
    'end_date': op.endDate == null ? null : dateToWire(op.endDate!),
    'enabled': op.enabled,
  };

  PlannedOp _toEntity(Map<String, dynamic> json) => PlannedOp(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    title: json['title'] as String,
    amount: (json['amount'] as num).toInt(),
    currencyCode: json['currency_code'] as String,
    kind: OpKind.fromWire(json['kind'] as String),
    category: OpCategory.fromWire(json['category'] as String? ?? 'other'),
    accountId: json['account_id'] as String?,
    schedule: Schedule.fromWire(json['schedule'] as String),
    startDate: dateFromWire(json['start_date'] as String),
    endDate: json['end_date'] == null
        ? null
        : dateFromWire(json['end_date'] as String),
    enabled: json['enabled'] as bool? ?? true,
  );
}
