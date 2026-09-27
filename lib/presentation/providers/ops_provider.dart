import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/planned_op.dart';
import 'repo_providers.dart';

const _uuid = Uuid();

/// The user's planned operations. Like accounts, writes go to the repository
/// first and the list is refetched afterwards.
class OpsNotifier extends AsyncNotifier<List<PlannedOp>> {
  @override
  Future<List<PlannedOp>> build() {
    // Per-user data: see [currentUserIdProvider].
    if (ref.watch(currentUserIdProvider) == null) {
      return Future.value(const <PlannedOp>[]);
    }
    return ref.watch(plannedOpsRepositoryProvider).getAll();
  }

  /// Builds a blank operation for the edit screen. Not persisted until saved.
  PlannedOp draft() {
    final today = DateTime.now();
    return PlannedOp(
      id: _uuid.v4(),
      userId: ref.read(currentUserIdProvider) ?? '',
      title: '',
      amount: 0,
      currencyCode: 'RUB',
      kind: OpKind.expense,
      schedule: Schedule.monthly,
      startDate: DateTime(today.year, today.month, today.day),
    );
  }

  Future<void> save(PlannedOp op) async {
    await ref.read(plannedOpsRepositoryProvider).save(op);
    ref.invalidateSelf();
    await future;
  }

  Future<void> setEnabled(PlannedOp op, {required bool enabled}) =>
      save(op.copyWith(enabled: enabled));

  Future<void> delete(String id) async {
    await ref.read(plannedOpsRepositoryProvider).delete(id);
    ref.invalidateSelf();
    await future;
  }
}

final opsProvider = AsyncNotifierProvider<OpsNotifier, List<PlannedOp>>(
  OpsNotifier.new,
);
