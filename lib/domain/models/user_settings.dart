import 'forecast_horizon.dart';
import 'amount_sort.dart';

/// Per-user preferences. Exactly one row per user.
class UserSettings {
  final String userId;

  /// Currency every total is reported in. Invariant: always one of the
  /// currencies of the user's non-archived accounts — see
  /// `normalizeBaseCurrency` in `lib/domain/projection/project_balance.dart`.
  final String baseCurrency;

  /// Forecast horizon the user last chose. Stored rather than kept in memory so
  /// it survives a restart instead of snapping back to «Через 30 дней».
  final ForecastPreset forecastPreset;

  /// The date behind [ForecastPreset.custom]. Date-only.
  final DateTime? forecastCustomDate;

  /// By-amount sort of the accounts on the home screen.
  final AmountSort accountsSort;

  /// By-amount sort of the operation categories and of the operations inside
  /// each one.
  final AmountSort opsSort;

  const UserSettings({
    required this.userId,
    required this.baseCurrency,
    this.forecastPreset = ForecastPreset.plus30,
    this.forecastCustomDate,
    this.accountsSort = AmountSort.desc,
    this.opsSort = AmountSort.desc,
  });

  ForecastHorizon get forecastHorizon =>
      ForecastHorizon(preset: forecastPreset, customDate: forecastCustomDate);

  UserSettings copyWith({
    String? baseCurrency,
    ForecastPreset? forecastPreset,
    DateTime? forecastCustomDate,
    AmountSort? accountsSort,
    AmountSort? opsSort,
  }) => UserSettings(
    userId: userId,
    baseCurrency: baseCurrency ?? this.baseCurrency,
    forecastPreset: forecastPreset ?? this.forecastPreset,
    forecastCustomDate: forecastCustomDate ?? this.forecastCustomDate,
    accountsSort: accountsSort ?? this.accountsSort,
    opsSort: opsSort ?? this.opsSort,
  );

  @override
  bool operator ==(Object other) =>
      other is UserSettings &&
      other.userId == userId &&
      other.baseCurrency == baseCurrency &&
      other.forecastPreset == forecastPreset &&
      other.forecastCustomDate == forecastCustomDate &&
      other.accountsSort == accountsSort &&
      other.opsSort == opsSort;

  @override
  int get hashCode => Object.hash(
    userId,
    baseCurrency,
    forecastPreset,
    forecastCustomDate,
    accountsSort,
    opsSort,
  );
}
