/// A place money sits: a card, a cash stash, a deposit.
///
/// [balance] is the single source of truth for "how much do I have" — planned
/// operations never change it (see `projectBalance`); only the user editing the
/// balance or a transfer does.
class Account {
  final String id;
  final String userId;
  final String name;
  final String currencyCode;

  /// Current balance in minor units of [currencyCode]. Can be negative.
  final int balance;

  /// Archived accounts stay for history but drop out of totals, forecasts and
  /// the base-currency candidate set.
  final bool archived;

  final int sortOrder;

  const Account({
    required this.id,
    required this.userId,
    required this.name,
    required this.currencyCode,
    this.balance = 0,
    this.archived = false,
    this.sortOrder = 0,
  });

  Account copyWith({
    String? name,
    String? currencyCode,
    int? balance,
    bool? archived,
    int? sortOrder,
  }) => Account(
    id: id,
    userId: userId,
    name: name ?? this.name,
    currencyCode: currencyCode ?? this.currencyCode,
    balance: balance ?? this.balance,
    archived: archived ?? this.archived,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.id == id &&
      other.userId == userId &&
      other.name == name &&
      other.currencyCode == currencyCode &&
      other.balance == balance &&
      other.archived == archived &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode =>
      Object.hash(id, userId, name, currencyCode, balance, archived, sortOrder);
}
