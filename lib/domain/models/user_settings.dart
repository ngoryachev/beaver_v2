import 'forecast_horizon.dart';

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

  const UserSettings({
    required this.userId,
    required this.baseCurrency,
    this.forecastPreset = ForecastPreset.plus30,
    this.forecastCustomDate,
  });

  ForecastHorizon get forecastHorizon =>
      ForecastHorizon(preset: forecastPreset, customDate: forecastCustomDate);

  UserSettings copyWith({
    String? baseCurrency,
    ForecastPreset? forecastPreset,
    DateTime? forecastCustomDate,
  }) => UserSettings(
    userId: userId,
    baseCurrency: baseCurrency ?? this.baseCurrency,
    forecastPreset: forecastPreset ?? this.forecastPreset,
    forecastCustomDate: forecastCustomDate ?? this.forecastCustomDate,
  );

  @override
  bool operator ==(Object other) =>
      other is UserSettings &&
      other.userId == userId &&
      other.baseCurrency == baseCurrency &&
      other.forecastPreset == forecastPreset &&
      other.forecastCustomDate == forecastCustomDate;

  @override
  int get hashCode =>
      Object.hash(userId, baseCurrency, forecastPreset, forecastCustomDate);
}
