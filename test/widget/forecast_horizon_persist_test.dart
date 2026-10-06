import 'package:beaver_v2/app.dart';
import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_scenarios_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/forecast_horizon.dart';
import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/models/scenario.dart';
import 'package:beaver_v2/domain/models/user_settings.dart';
import 'package:beaver_v2/domain/projection/occurrences.dart';
import 'package:beaver_v2/presentation/format/money_format.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/screens/forecast/forecast_screen.dart';
import 'package:beaver_v2/presentation/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// The chosen horizon used to be local state of the forecast screen, so leaving
/// the screen reset it and the home card always claimed «Через 30 дней». It now
/// lives in the settings row: these tests follow one choice from the chip to the
/// repository and back out onto the home screen.
const _userId = 'u1';

final _today = dateOnly(DateTime.now());

/// 100 ₽ a day, so the balance after N days is a number the test can compute.
final _daily = PlannedOp(
  id: 'op1',
  userId: _userId,
  title: 'Обед',
  amount: 10000,
  currencyCode: 'RUB',
  kind: OpKind.expense,
  schedule: Schedule.daily,
  startDate: _today,
);

/// One settings repository shared by every pump below: that is what makes a
/// second pump a "restart" rather than a fresh user.
late InMemorySettingsRepository _settings;

List<Override> _overrides() => [
  currentUserIdProvider.overrideWithValue(_userId),
  accountsRepositoryProvider.overrideWithValue(
    InMemoryAccountsRepository(const [
      Account(
        id: 'a1',
        userId: _userId,
        name: 'Карта',
        currencyCode: 'RUB',
        // 100 000 ₽: enough to stay positive over every horizon used here.
        balance: 10000000,
      ),
    ]),
  ),
  plannedOpsRepositoryProvider.overrideWithValue(
    InMemoryPlannedOpsRepository([_daily]),
  ),
  scenariosRepositoryProvider.overrideWithValue(
    InMemoryScenariosRepository([
      Scenario(id: 's1', userId: _userId, name: 'Все', isDefault: true),
    ]),
  ),
  ratesRepositoryProvider.overrideWithValue(
    InMemoryRatesRepository(const []),
  ),
  settingsRepositoryProvider.overrideWithValue(_settings),
];

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: BeaverApp.supportedLocales,
        localizationsDelegates: BeaverApp.localizationsDelegates,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The forecast figure on the home card, read off its keyed widget.
String _homeForecast(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('home-forecast-30'))).data!;

bool _chipSelected(WidgetTester tester, String label) =>
    tester.widget<FilterChip>(find.widgetWithText(FilterChip, label)).selected;

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  setUp(() {
    _settings = InMemorySettingsRepository(
      const UserSettings(userId: _userId, baseCurrency: 'RUB'),
    );
  });

  testWidgets('+30 дней is still the default', (tester) async {
    await _pump(tester, const ForecastScreen());

    expect(_chipSelected(tester, '+30 дней'), isTrue);

    await _pump(tester, const HomeScreen());
    expect(find.text('Через 30 дней'), findsOneWidget);
  });

  testWidgets('a chosen preset is stored and survives a rebuild', (
    tester,
  ) async {
    await _pump(tester, const ForecastScreen());

    await tester.tap(find.text('+90 дней'));
    await tester.pumpAndSettle();

    final stored = await _settings.get();
    expect(stored!.forecastPreset, ForecastPreset.plus90);

    // Rebuilt from scratch — as after a restart — the chip is still the one.
    await _pump(tester, const ForecastScreen());
    expect(_chipSelected(tester, '+90 дней'), isTrue);
    expect(_chipSelected(tester, '+30 дней'), isFalse);
    expect(find.text(formatDate(addDays(_today, 90))), findsOneWidget);
  });

  testWidgets('the home card names the chosen horizon and uses it', (
    tester,
  ) async {
    await _pump(tester, const ForecastScreen());
    await tester.tap(find.text('+90 дней'));
    await tester.pumpAndSettle();

    await _pump(tester, const HomeScreen());

    expect(find.text('Через 90 дней'), findsOneWidget);
    expect(find.text('Через 30 дней'), findsNothing);
    // Today plus 90 more days, each firing once.
    expect(_homeForecast(tester), formatMoney(10000000 - 91 * 10000, 'RUB'));
  });

  testWidgets('«Конец месяца» is named on the home card', (tester) async {
    await _pump(tester, const ForecastScreen());
    await tester.tap(find.text('Конец месяца'));
    await tester.pumpAndSettle();

    await _pump(tester, const HomeScreen());

    expect(find.text('Конец месяца'), findsOneWidget);
  });

  testWidgets('a custom date shows as a date on the home card', (tester) async {
    final target = addDays(_today, 45);
    await _settings.save(
      UserSettings(
        userId: _userId,
        baseCurrency: 'RUB',
        forecastPreset: ForecastPreset.custom,
        forecastCustomDate: target,
      ),
    );

    await _pump(tester, const HomeScreen());

    expect(find.text(formatDate(target)), findsOneWidget);
    expect(_homeForecast(tester), formatMoney(10000000 - 46 * 10000, 'RUB'));
  });

  testWidgets('an expired stored date leaves the screen on the default window', (
    tester,
  ) async {
    // Persisting the date means it outlives the session that picked it: by
    // today it can be in the past. Such a horizon is dropped on read, so the
    // chips are back to the default and «Другая дата» opens a picker whose
    // initial date is a day it will accept — `showDatePicker` asserts on an
    // `initialDate` before its `firstDate`.
    await _settings.save(
      UserSettings(
        userId: _userId,
        baseCurrency: 'RUB',
        forecastPreset: ForecastPreset.custom,
        forecastCustomDate: addDays(_today, -10),
      ),
    );

    await _pump(tester, const ForecastScreen());

    expect(_chipSelected(tester, '+30 дней'), isTrue);
    expect(find.text(formatDate(addDays(_today, -10))), findsNothing);
    expect(find.text(formatDate(addDays(_today, 30))), findsOneWidget);

    await tester.tap(find.text('Другая дата'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('a stored custom date in the past is not shown as the horizon', (
    tester,
  ) async {
    // Persisting the date means it outlives the session that picked it. Once it
    // is behind us `projectionProvider` clamps the window to today, so the card
    // shows today's balance under a title naming a date that has already gone —
    // the figure and the date it is labelled with no longer match.
    final stale = addDays(_today, -10);
    await _settings.save(
      UserSettings(
        userId: _userId,
        baseCurrency: 'RUB',
        forecastPreset: ForecastPreset.custom,
        forecastCustomDate: stale,
      ),
    );

    await _pump(tester, const HomeScreen());

    expect(
      find.text(formatDate(stale)),
      findsNothing,
      reason: 'a horizon in the past is not a horizon the card can advertise',
    );
  });

  testWidgets('a stored custom date in the past still forecasts something', (
    tester,
  ) async {
    final stale = addDays(_today, -10);
    await _settings.save(
      UserSettings(
        userId: _userId,
        baseCurrency: 'RUB',
        forecastPreset: ForecastPreset.custom,
        forecastCustomDate: stale,
      ),
    );

    await _pump(tester, const ForecastScreen());

    // With the window collapsed to a single day there is no curve and no event
    // list left — the forecast screen goes blank with nothing explaining why.
    expect(
      find.text('Слишком короткий период для графика'),
      findsNothing,
      reason: 'a stale stored date must not empty out the forecast screen',
    );
  });

  testWidgets('tomorrow is the shortest horizon the card will name', (
    tester,
  ) async {
    // The boundary on the other side of "expired": the day after today is
    // still a horizon, and nothing may round it away.
    final target = addDays(_today, 1);
    await _settings.save(
      UserSettings(
        userId: _userId,
        baseCurrency: 'RUB',
        forecastPreset: ForecastPreset.custom,
        forecastCustomDate: target,
      ),
    );

    await _pump(tester, const HomeScreen());
    expect(find.text(formatDate(target)), findsOneWidget);
    expect(_homeForecast(tester), formatMoney(10000000 - 2 * 10000, 'RUB'));

    await _pump(tester, const ForecastScreen());
    expect(_chipSelected(tester, formatDate(target)), isTrue);
    expect(_chipSelected(tester, '+30 дней'), isFalse);
  });

  testWidgets('an expired date left in the row does not break the picker', (
    tester,
  ) async {
    // Choosing a preset keeps the stored date around on purpose, so after this
    // detour the row holds «plus90 + a date from last week» — a shape
    // `isExpired` says nothing about, since the preset is not custom. Going
    // back to «Другая дата» then hands that date to `showDatePicker`, which
    // asserts on an `initialDate` before its `firstDate`.
    await _settings.save(
      UserSettings(
        userId: _userId,
        baseCurrency: 'RUB',
        forecastPreset: ForecastPreset.custom,
        forecastCustomDate: addDays(_today, -7),
      ),
    );

    await _pump(tester, const ForecastScreen());
    await tester.tap(find.text('+90 дней'));
    await tester.pumpAndSettle();
    expect(_chipSelected(tester, '+90 дней'), isTrue);

    await tester.tap(find.text('Другая дата'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('cycling the base currency does not reset the horizon', (
    tester,
  ) async {
    // `setBaseCurrency` used to rebuild the settings row from scratch, which
    // would wipe the horizon on every tap of the total.
    await _settings.save(
      const UserSettings(
        userId: _userId,
        baseCurrency: 'RUB',
        forecastPreset: ForecastPreset.plus90,
      ),
    );

    await _pump(tester, const HomeScreen());
    expect(find.text('Через 90 дней'), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-total')));
    await tester.pumpAndSettle();

    expect((await _settings.get())!.forecastPreset, ForecastPreset.plus90);
    expect(find.text('Через 90 дней'), findsOneWidget);
  });
}
