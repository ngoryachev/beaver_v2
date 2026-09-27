import '../models/planned_op.dart';

abstract class PlannedOpsRepository {
  Future<List<PlannedOp>> getAll();

  Future<void> save(PlannedOp op);

  Future<void> delete(String id);
}
