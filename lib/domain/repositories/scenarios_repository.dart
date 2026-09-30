import '../models/scenario.dart';

abstract class ScenariosRepository {
  Future<List<Scenario>> getAll();

  Future<void> save(Scenario scenario);

  Future<void> delete(String id);
}
