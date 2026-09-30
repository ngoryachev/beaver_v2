/// A "what if" view: the same data with some accounts and operations switched
/// off. Exclusions are stored, not inclusions, so anything created later is
/// automatically part of every scenario.
class Scenario {
  final String id;
  final String userId;
  final String name;

  /// The built-in «Все» scenario: excludes nothing and cannot be deleted.
  final bool isDefault;

  final Set<String> disabledAccountIds;
  final Set<String> disabledOpIds;

  Scenario({
    required this.id,
    required this.userId,
    required this.name,
    this.isDefault = false,
    Set<String> disabledAccountIds = const {},
    Set<String> disabledOpIds = const {},
  }) : disabledAccountIds = Set.unmodifiable(disabledAccountIds),
       disabledOpIds = Set.unmodifiable(disabledOpIds);

  bool allowsAccount(String accountId) =>
      !disabledAccountIds.contains(accountId);
  bool allowsOp(String opId) => !disabledOpIds.contains(opId);

  @override
  bool operator ==(Object other) =>
      other is Scenario &&
      other.id == id &&
      other.userId == userId &&
      other.name == name &&
      other.isDefault == isDefault &&
      _setEquals(other.disabledAccountIds, disabledAccountIds) &&
      _setEquals(other.disabledOpIds, disabledOpIds);

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    name,
    isDefault,
    Object.hashAllUnordered(disabledAccountIds),
    Object.hashAllUnordered(disabledOpIds),
  );

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}
