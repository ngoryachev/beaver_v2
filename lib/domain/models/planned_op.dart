/// Whether an operation adds to or subtracts from the balance. [PlannedOp.amount]
/// is always positive; the kind carries the sign.
enum OpKind {
  income('income'),
  expense('expense');

  final String wire;
  const OpKind(this.wire);

  static OpKind fromWire(String value) =>
      OpKind.values.firstWhere((kind) => kind.wire == value);

  /// Multiplier applied to the amount when projecting a balance.
  int get sign => this == OpKind.income ? 1 : -1;
}

/// Coarse grouping used to sort the operations list. Deliberately a closed set:
/// user-defined categories are out of scope.
enum OpCategory {
  food('food'),
  shopping('shopping'),
  services('services'),
  housing('housing'),
  utilities('utilities'),
  health('health'),
  education('education'),
  software('software'),
  travel('travel'),
  fun('fun'),
  debt('debt'),
  salary('salary'),
  other('other');

  final String wire;
  const OpCategory(this.wire);

  static OpCategory fromWire(String value) => OpCategory.values.firstWhere(
    (category) => category.wire == value,
    orElse: () => other,
  );
}

/// How often an operation repeats. `once` fires on [PlannedOp.startDate] only.
enum Schedule {
  once('once'),
  daily('daily'),
  weekly('weekly'),
  biweekly('biweekly'),
  monthly('monthly'),
  yearly('yearly');

  final String wire;
  const Schedule(this.wire);

  static Schedule fromWire(String value) =>
      Schedule.values.firstWhere((schedule) => schedule.wire == value);
}

/// A recurring (or one-off) money movement the user expects. Planned operations
/// are a forecast input only: they never mutate an [Account] balance.
class PlannedOp {
  final String id;
  final String userId;
  final String title;

  /// Always positive, in minor units of [currencyCode]. Direction lives in [kind].
  final int amount;

  final String currencyCode;
  final OpKind kind;
  final OpCategory category;

  /// Account the operation hits. `null` means "any account" — the amount still
  /// affects the overall total, just not a specific account.
  final String? accountId;

  final Schedule schedule;

  /// First possible occurrence. Date-only: the time part is ignored.
  final DateTime startDate;

  /// Last possible occurrence, inclusive. `null` means open-ended.
  final DateTime? endDate;

  final bool enabled;

  const PlannedOp({
    required this.id,
    required this.userId,
    required this.title,
    required this.amount,
    required this.currencyCode,
    required this.kind,
    this.category = OpCategory.other,
    this.accountId,
    required this.schedule,
    required this.startDate,
    this.endDate,
    this.enabled = true,
  });

  PlannedOp copyWith({
    String? title,
    int? amount,
    String? currencyCode,
    OpKind? kind,
    OpCategory? category,
    String? accountId,
    bool clearAccountId = false,
    Schedule? schedule,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    bool? enabled,
  }) => PlannedOp(
    id: id,
    userId: userId,
    title: title ?? this.title,
    amount: amount ?? this.amount,
    currencyCode: currencyCode ?? this.currencyCode,
    kind: kind ?? this.kind,
    category: category ?? this.category,
    accountId: clearAccountId ? null : (accountId ?? this.accountId),
    schedule: schedule ?? this.schedule,
    startDate: startDate ?? this.startDate,
    endDate: clearEndDate ? null : (endDate ?? this.endDate),
    enabled: enabled ?? this.enabled,
  );

  /// Signed amount in minor units: negative for an expense.
  int get signedAmount => amount * kind.sign;

  @override
  bool operator ==(Object other) =>
      other is PlannedOp &&
      other.id == id &&
      other.userId == userId &&
      other.title == title &&
      other.amount == amount &&
      other.currencyCode == currencyCode &&
      other.kind == kind &&
      other.category == category &&
      other.accountId == accountId &&
      other.schedule == schedule &&
      other.startDate == startDate &&
      other.endDate == endDate &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    title,
    amount,
    currencyCode,
    kind,
    category,
    accountId,
    schedule,
    startDate,
    endDate,
    enabled,
  );
}
