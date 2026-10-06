import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/forecast_horizon.dart';
import '../../../domain/models/planned_op.dart';
import '../../../domain/projection/occurrences.dart';
import '../../../domain/projection/project_balance.dart';
import '../../format/money_format.dart';
import '../../providers/forecast_horizon_provider.dart';
import '../../providers/projection_provider.dart';
import '../../providers/scenarios_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/write_guard.dart';
import '../ops/op_labels.dart';

class ForecastScreen extends ConsumerStatefulWidget {
  const ForecastScreen({super.key});

  @override
  ConsumerState<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends ConsumerState<ForecastScreen> {
  /// The horizon lives in the settings row, not in this state: it is the one
  /// choice on this screen the user expects to find again, both after a restart
  /// and on the preview card on the home screen.
  Future<void> _select(ForecastHorizon horizon) => runWrite(
    context,
    () => ref.read(settingsProvider.notifier).setForecastHorizon(horizon),
    failureMessage: 'Не удалось сохранить горизонт прогноза',
  );

  Future<void> _pickCustomDate(ForecastHorizon horizon) async {
    final today = dateOnly(DateTime.now());
    final stored = horizon.customDate;
    // `showDatePicker` asserts on an `initialDate` before `firstDate`, and a
    // persisted date outlives the session that picked it. `forecastHorizonProvider`
    // already drops an expired one; this is the picker's own floor.
    final initialDate = stored == null || stored.isBefore(today)
        ? addDays(today, 30)
        : stored;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: DateTime(today.year + 10),
    );
    if (picked == null || !mounted) return;
    await _select(
      ForecastHorizon(
        preset: ForecastPreset.custom,
        customDate: DateTime(picked.year, picked.month, picked.day),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseCurrency = ref.watch(baseCurrencyProvider);
    final scenario = ref.watch(activeScenarioProvider);
    final horizon = ref.watch(forecastHorizonProvider);
    final targetDate = ref.watch(forecastTargetDateProvider);
    final projection = ref.watch(projectionProvider(targetDate));

    return Scaffold(
      appBar: AppBar(title: const Text('Прогноз')),
      body: CustomScrollView(
        slivers: [
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _presetChip(
                      'Конец месяца',
                      ForecastPreset.endOfMonth,
                      horizon,
                    ),
                    _presetChip('+30 дней', ForecastPreset.plus30, horizon),
                    _presetChip('+90 дней', ForecastPreset.plus90, horizon),
                    FilterChip(
                      label: Text(
                        horizon.preset == ForecastPreset.custom &&
                                horizon.customDate != null
                            ? formatDate(horizon.customDate!)
                            : 'Другая дата',
                      ),
                      avatar: const Icon(Icons.event, size: 18),
                      selected: horizon.preset == ForecastPreset.custom,
                      onSelected: (_) => _pickCustomDate(horizon),
                    ),
                  ],
                ),
              ),
              if (scenario != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Сценарий: ${scenario.name}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (projection.missingRateCodes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.currency_exchange,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Нет курса для '
                              '${projection.missingRateCodes.join(', ')}. '
                              'Эти суммы не учтены в прогнозе.',
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Kept apart from the missing-rate card: these currencies have
              // a rate, the amount is simply past what can be expressed.
              if (projection.unconvertibleCodes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Слишком большие суммы в '
                              '${projection.unconvertibleCodes.join(', ')} — '
                              'их не удалось пересчитать, и в прогноз они не '
                              'вошли.',
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: _summaryTile(
                        label: 'Сейчас',
                        value: formatMoney(
                          projection.startBalance,
                          baseCurrency,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summaryTile(
                        label: formatDate(targetDate),
                        value: formatMoney(projection.endBalance, baseCurrency),
                        isNegative: projection.endBalance < 0,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _summaryTile(
                  label: 'Минимум · ${formatDate(projection.minDate)}',
                  value: formatMoney(projection.minBalance, baseCurrency),
                  isNegative: projection.minBalance < 0,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 240,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16, top: 8),
                  child: _BalanceChart(
                    projection: projection,
                    baseCurrency: baseCurrency,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('События', style: theme.textTheme.titleMedium),
              ),
            ]),
          ),
          if (projection.events.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'В этом периоде операций нет.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            // Built on demand: a custom date years out over a daily operation
            // runs to thousands of events, and a child list would build every
            // tile on every rebuild of the screen.
            SliverList.builder(
              itemCount: projection.events.length,
              itemBuilder: (context, index) => _EventTile(
                event: projection.events[index],
                baseCurrency: baseCurrency,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _presetChip(
    String label,
    ForecastPreset preset,
    ForecastHorizon horizon,
  ) => FilterChip(
    label: Text(label),
    selected: horizon.preset == preset,
    onSelected: (_) => _select(
      // The custom date rides along, so «Другая дата» still shows it after a
      // detour through another preset.
      ForecastHorizon(preset: preset, customDate: horizon.customDate),
    ),
  );

  Widget _summaryTile({
    required String label,
    required String value,
    bool isNegative = false,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                color: isNegative ? theme.colorScheme.error : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The balance curve. One point per day, with a zero line whenever the forecast
/// crosses it — that crossing is the whole reason to look at the chart.
class _BalanceChart extends StatelessWidget {
  final ProjectionResult projection;
  final String baseCurrency;

  const _BalanceChart({required this.projection, required this.baseCurrency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = projection.points;
    if (points.length < 2) {
      return const Center(child: Text('Слишком короткий период для графика'));
    }

    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].balanceMinor / 100),
    ];
    final values = spots.map((spot) => spot.y);
    final rawMin = values.reduce((a, b) => a < b ? a : b);
    final rawMax = values.reduce((a, b) => a > b ? a : b);

    // Snap the axis to a round step so every gridline label is a clean number
    // rather than the padded extreme of the data.
    final step = _niceStep(rawMax - rawMin);
    var minY = (rawMin / step).floorToDouble() * step;
    var maxY = (rawMax / step).ceilToDouble() * step;
    if (minY == maxY) maxY = minY + step;
    // Keep zero on the axis when the balance crosses it — that crossing is the
    // whole point of looking at the chart.
    if (rawMin < 0 && minY > 0) minY = 0;

    // Roughly five date labels whatever the horizon is.
    final dateStep = (points.length / 5).ceil();

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: step,
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 64,
              interval: step,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  // No symbol here: the summary tiles above already carry it,
                  // and it would only make the labels wrap.
                  formatMoneyCompact(
                    (value * 100).round(),
                    baseCurrency,
                    withSymbol: false,
                  ),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: dateStep.toDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                // fl_chart also offers the axis extremes; drawing those would
                // collide with the last on-grid label.
                if (index % dateStep != 0) return const SizedBox.shrink();
                final date = points[index].date;
                return Text(
                  '${date.day}.${date.month}',
                  style: theme.textTheme.bodySmall,
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: rawMin < 0
            ? ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: 0,
                    color: theme.colorScheme.error,
                    strokeWidth: 1,
                    dashArray: const [4, 4],
                  ),
                ],
              )
            : const ExtraLinesData(),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => [
              for (final spot in touched)
                LineTooltipItem(
                  '${formatDate(points[spot.x.round()].date)}\n'
                  '${formatMoney((spot.y * 100).round(), baseCurrency)}',
                  TextStyle(color: theme.colorScheme.onInverseSurface),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: theme.colorScheme.primary,
            barWidth: 2,
            // One dot per day would be unreadable over a 90-day horizon.
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 1/2/5 × 10^n step just below a fifth of the range, so the axis lands on
/// round numbers at both ends.
double _niceStep(double range) {
  if (range <= 0 || !range.isFinite) return 1;
  final target = range / 4;
  final magnitude = math
      .pow(10, (math.log(target) / math.ln10).floor())
      .toDouble();
  for (final multiple in const [1.0, 2.0, 5.0]) {
    if (magnitude * multiple >= target) return magnitude * multiple;
  }
  return magnitude * 10;
}

class _EventTile extends StatelessWidget {
  final ProjectionEvent event;
  final String baseCurrency;

  const _EventTile({required this.event, required this.baseCurrency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final op = event.op;
    final isIncome = op.kind == OpKind.income;
    final ownCurrency =
        op.currencyCode.toUpperCase() != baseCurrency.toUpperCase();

    return ListTile(
      dense: true,
      leading: Icon(categoryIcon(op.category), size: 20),
      title: Text(op.title),
      subtitle: Text(formatDayMonth(event.date)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${isIncome ? '+' : '−'}'
            '${formatMoney(op.amount, op.currencyCode)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isIncome ? Colors.green.shade700 : theme.colorScheme.error,
            ),
          ),
          if (ownCurrency)
            Text(
              event.baseAmountMinor == null
                  ? 'нет курса'
                  : '≈ ${formatMoney(event.baseAmountMinor!.abs(), baseCurrency)}',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
