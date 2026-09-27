import '../../domain/models/planned_op.dart';
import '../../domain/repositories/planned_ops_repository.dart';

class InMemoryPlannedOpsRepository implements PlannedOpsRepository {
  final Map<String, PlannedOp> _ops = {};

  InMemoryPlannedOpsRepository([List<PlannedOp> seed = const []]) {
    for (final op in seed) {
      _ops[op.id] = op;
    }
  }

  @override
  Future<List<PlannedOp>> getAll() async {
    final all = _ops.values.toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    return all;
  }

  @override
  Future<void> save(PlannedOp op) async {
    _ops[op.id] = op;
  }

  @override
  Future<void> delete(String id) async {
    _ops.remove(id);
  }
}
