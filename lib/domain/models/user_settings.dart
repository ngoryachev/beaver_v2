/// Per-user preferences. Exactly one row per user.
class UserSettings {
  final String userId;

  /// Currency every total is reported in. Invariant: always one of the
  /// currencies of the user's non-archived accounts — see
  /// `normalizeBaseCurrency` in `lib/domain/projection/project_balance.dart`.
  final String baseCurrency;

  const UserSettings({required this.userId, required this.baseCurrency});

  @override
  bool operator ==(Object other) =>
      other is UserSettings &&
      other.userId == userId &&
      other.baseCurrency == baseCurrency;

  @override
  int get hashCode => Object.hash(userId, baseCurrency);
}
