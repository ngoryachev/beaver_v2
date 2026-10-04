import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/forecast_horizon.dart';
import '../format/money_format.dart';
import 'settings_provider.dart';

/// The horizon the user last chose, read from the stored settings.
///
/// Shared by the forecast screen and the preview card on the home screen, so
/// picking «+90 дней» in one is reflected in the other — and survives a restart.
final forecastHorizonProvider = Provider<ForecastHorizon>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return settings?.forecastHorizon ?? const ForecastHorizon();
});

/// The date the projection runs to.
///
/// Date-only on purpose: `projectionProvider` is a `Provider.family` whose cache
/// is keyed by its argument, so feeding it a `DateTime.now()` would leave one
/// dead projection behind on every rebuild.
final forecastTargetDateProvider = Provider<DateTime>(
  (ref) => ref.watch(forecastHorizonProvider).targetDate(DateTime.now()),
);

/// Full-sentence name of a horizon, for a card title. The chips on the forecast
/// screen use their own, shorter labels.
String horizonLabel(ForecastHorizon horizon) => switch (horizon.preset) {
  ForecastPreset.endOfMonth => 'Конец месяца',
  ForecastPreset.plus30 => 'Через 30 дней',
  ForecastPreset.plus90 => 'Через 90 дней',
  // Falling back to the +30 wording matches `targetDate`, which also treats a
  // custom preset with no date as +30 days.
  ForecastPreset.custom => horizon.customDate == null
      ? 'Через 30 дней'
      : formatDate(horizon.customDate!),
};
