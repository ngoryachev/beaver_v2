import '../projection/occurrences.dart';

/// Ready-made forecast horizons. «Конец месяца» is first because "will I make
/// it to payday" is the question the forecast exists for.
enum ForecastPreset {
  endOfMonth('end_of_month'),
  plus30('plus30'),
  plus90('plus90'),
  custom('custom');

  final String wire;
  const ForecastPreset(this.wire);

  /// Falls back to [plus30] rather than throwing: the value comes from a column
  /// a newer build may have written, and an unreadable horizon must not take the
  /// whole settings row — and with it the base currency — down.
  static ForecastPreset fromWire(String? value) => ForecastPreset.values
      .firstWhere((preset) => preset.wire == value, orElse: () => plus30);
}

/// How far ahead the forecast looks: a preset plus, for [ForecastPreset.custom],
/// the date the user picked.
class ForecastHorizon {
  final ForecastPreset preset;

  /// Only meaningful for [ForecastPreset.custom]. Kept when another preset is
  /// selected so going back to «Другая дата» remembers it.
  final DateTime? customDate;

  const ForecastHorizon({this.preset = ForecastPreset.plus30, this.customDate});

  /// The date the projection runs to, given today's date.
  ///
  /// Always date-only: `projectionProvider` is a family whose cache is keyed by
  /// its argument, so a value carrying a time component would leave one dead
  /// projection behind per rebuild.
  DateTime targetDate(DateTime today) {
    final from = dateOnly(today);
    return switch (preset) {
      ForecastPreset.endOfMonth => DateTime(
        from.year,
        from.month,
        daysInMonth(from.year, from.month),
      ),
      // Calendar days, not 24-hour durations: across a DST transition
      // `from.add(Duration(days: 30))` lands on day 29 at 23:00.
      ForecastPreset.plus30 => addDays(from, 30),
      ForecastPreset.plus90 => addDays(from, 90),
      ForecastPreset.custom => customDate == null
          ? addDays(from, 30)
          : dateOnly(customDate!),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ForecastHorizon &&
      other.preset == preset &&
      other.customDate == customDate;

  @override
  int get hashCode => Object.hash(preset, customDate);
}
