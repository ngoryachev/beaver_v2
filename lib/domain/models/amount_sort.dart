/// Direction of a by-amount sort on the home screen. Two states only: the
/// sort button flips between them.
enum AmountSort {
  asc('asc'),
  desc('desc');

  final String wire;
  const AmountSort(this.wire);

  /// Falls back to [desc] rather than throwing, for the same reason as
  /// `ForecastPreset.fromWire`: an unreadable value must not take the whole
  /// settings row down.
  static AmountSort fromWire(String? value) => AmountSort.values.firstWhere(
    (direction) => direction.wire == value,
    orElse: () => desc,
  );

  AmountSort get toggled => this == asc ? desc : asc;
}
