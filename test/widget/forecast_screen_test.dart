import 'package:beaver_v2/app.dart';
import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_scenarios_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/models/scenario.dart';
import 'package:beaver_v2/domain/models/user_settings.dart';
import 'package:beaver_v2/domain/projection/occurrences.dart';
import 'package:beaver_v2/presentation/format/money_format.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/screens/forecast/forecast_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _userId = 'u1';

final _today = dateOnly(DateTime.now());

Account _account({
  required String id,
  required String code,
  required int balance,
}) => Account(
  id: id,
  userId: _userId,
  name: 'Счёт $id',
  currencyCode: code,
  balance: balance,
);

PlannedOp _op({
  required String id,
  required String title,
  required int amount,
  String code = 'RUB',
  OpKind kind = OpKind.expense,
  Schedule schedule = Schedule.daily,
  DateTime? startDate,
}) => PlannedOp(
  id: id,
  userId: _userId,
  title: title,
  amount: amount,
  currencyCode: code,
  kind: kind,
  schedule: schedule,
  startDate: startDate ?? _today,
);

Future<void> _pumpForecast(
  WidgetTester tester, {
  required List<Account> accounts,
  List<PlannedOp> ops = const [],
  List<Rate> rates = const [],
  String baseCurrency = 'RUB',
}) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_userId),
        accountsRepositoryProvider.overrideWithValue(
          InMemoryAccountsRepository(accounts),
        ),
        plannedOpsRepositoryProvider.overrideWithValue(
          InMemoryPlannedOpsRepository(ops),
        ),
        scenariosRepositoryProvider.overrideWithValue(
          InMemoryScenariosRepository([
            Scenario(id: 's1', userId: _userId, name: 'Все', isDefault: true),
          ]),
        ),
        ratesRepositoryProvider.overrideWithValue(
          InMemoryRatesRepository(rates),
        ),
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(
            UserSettings(userId: _userId, baseCurrency: baseCurrency),
          ),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: BeaverApp.supportedLocales,
        localizationsDelegates: BeaverApp.localizationsDelegates,
        home: const ForecastScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('the horizon presets', () {
    testWidgets('+30 дней is the default and spans 30 calendar days', (
      tester,
    ) async {
      await _pumpForecast(
        tester,
        accounts: [_account(id: 'a1', code: 'RUB', balance: 1000000)],
        // 100 ₽ a day: the end balance pins the horizon down exactly.
        ops: [_op(id: 'o1', title: 'Кофе', amount: 10000)],
      );

      // Today plus 30 more days, each firing once.
      expect(find.text(formatDate(addDays(_today, 30))), findsOneWidget);
      expect(find.text(formatMoney(1000000 - 31 * 10000, 'RUB')), findsWidgets);
    });

    testWidgets('+90 дней moves the horizon', (tester) async {
      await _pumpForecast(
        tester,
        accounts: [_account(id: 'a1', code: 'RUB', balance: 10000000)],
        ops: [_op(id: 'o1', title: 'Кофе', amount: 10000)],
      );

      await tester.tap(find.text('+90 дней'));
      await tester.pumpAndSettle();

      expect(find.text(formatDate(addDays(_today, 90))), findsOneWidget);
      expect(
        find.text(formatMoney(10000000 - 91 * 10000, 'RUB')),
        findsWidgets,
      );
    });

    testWidgets('«Конец месяца» targets the last day of the current month', (
      tester,
    ) async {
      await _pumpForecast(
        tester,
        accounts: [_account(id: 'a1', code: 'RUB', balance: 1000000)],
      );

      await tester.tap(find.text('Конец месяца'));
      await tester.pumpAndSettle();

      final lastDay = DateTime(
        _today.year,
        _today.month,
        daysInMonth(_today.year, _today.month),
      );
      expect(find.text(formatDate(lastDay)), findsOneWidget);
    });
  });

  group('the summary', () {
    testWidgets('«Сейчас» is the untouched account total', (tester) async {
      await _pumpForecast(
        tester,
        accounts: [
          _account(id: 'a1', code: 'RUB', balance: 1000000),
          _account(id: 'a2', code: 'RUB', balance: 250000),
        ],
        ops: [_op(id: 'o1', title: 'Кофе', amount: 10000)],
      );

      // Planned operations never move a balance, only the forecast.
      expect(find.text('Сейчас'), findsOneWidget);
      expect(find.text(formatMoney(1250000, 'RUB')), findsOneWidget);
    });

    testWidgets('the minimum and its date are shown', (tester) async {
      await _pumpForecast(
        tester,
        accounts: [_account(id: 'a1', code: 'RUB', balance: 50000)],
        // 200 ₽ a day against 500 ₽: the balance goes under within the window.
        ops: [_op(id: 'o1', title: 'Кофе', amount: 20000)],
      );

      // Minimum is reached on the last day of the window, not on day one.
      expect(
        find.text('Минимум · ${formatDate(addDays(_today, 30))}'),
        findsOneWidget,
      );
      expect(find.text(formatMoney(50000 - 31 * 20000, 'RUB')), findsWidgets);
    });

    testWidgets('a chart is drawn for a multi-day window', (tester) async {
      await _pumpForecast(
        tester,
        accounts: [_account(id: 'a1', code: 'RUB', balance: 1000000)],
      );

      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text('Слишком короткий период для графика'), findsNothing);
    });
  });

  group('events', () {
    testWidgets('an empty window says so', (tester) async {
      await _pumpForecast(
        tester,
        accounts: [_account(id: 'a1', code: 'RUB', balance: 1000000)],
      );

      expect(find.text('В этом периоде операций нет.'), findsOneWidget);
    });

    testWidgets('a one-off operation is listed once with its own amount', (
      tester,
    ) async {
      await _pumpForecast(
        tester,
        accounts: [_account(id: 'a1', code: 'RUB', balance: 1000000)],
        ops: [
          _op(
            id: 'o1',
            title: 'Страховка',
            amount: 450000,
            schedule: Schedule.once,
            startDate: addDays(_today, 5),
          ),
        ],
      );

      expect(find.text('Страховка'), findsOneWidget);
      expect(find.text('−${formatMoney(450000, 'RUB')}'), findsOneWidget);
      expect(find.text(formatDayMonth(addDays(_today, 5))), findsOneWidget);
    });

    testWidgets('a disabled operation is not projected', (tester) async {
      await _pumpForecast(
        tester,
        accounts: [_account(id: 'a1', code: 'RUB', balance: 1000000)],
        ops: [
          PlannedOp(
            id: 'o1',
            userId: _userId,
            title: 'Выключено',
            amount: 10000,
            currencyCode: 'RUB',
            kind: OpKind.expense,
            schedule: Schedule.daily,
            startDate: _today,
            enabled: false,
          ),
        ],
      );

      expect(find.text('В этом периоде операций нет.'), findsOneWidget);
      expect(find.text(formatMoney(1000000, 'RUB')), findsWidgets);
    });
  });

  group('missing rates', () {
    testWidgets('warn instead of counting the amount as zero', (tester) async {
      await _pumpForecast(
        tester,
        accounts: [
          _account(id: 'a1', code: 'RUB', balance: 1000000),
          // No RUB↔EUR rate is stored, so this balance cannot be converted.
          _account(id: 'a2', code: 'EUR', balance: 50000),
        ],
      );

      expect(find.textContaining('Нет курса для EUR'), findsOneWidget);
      expect(find.textContaining('не учтены в прогнозе'), findsOneWidget);
      // The convertible part is still reported, untouched by the gap.
      expect(find.text(formatMoney(1000000, 'RUB')), findsWidgets);
    });

    testWidgets('a convertible currency raises no warning', (tester) async {
      await _pumpForecast(
        tester,
        accounts: [
          _account(id: 'a1', code: 'RUB', balance: 1000000),
          _account(id: 'a2', code: 'EUR', balance: 50000),
        ],
        rates: [
          Rate(
            userId: _userId,
            code: 'RUB',
            ratePerUsd: 90,
            source: RateSource.auto,
            updatedAt: DateTime.now().toUtc(),
          ),
          Rate(
            userId: _userId,
            code: 'EUR',
            ratePerUsd: 0.9,
            source: RateSource.auto,
            updatedAt: DateTime.now().toUtc(),
          ),
        ],
      );

      expect(find.textContaining('Нет курса'), findsNothing);
      // 500 € → 555.56 $ → 50 000 ₽, on top of the 10 000 ₽ already there. With
      // no operations, «Сейчас», the horizon and the minimum all show it.
      expect(find.text(formatMoney(1000000 + 5000000, 'RUB')), findsNWidgets(3));
    });

    testWidgets('an unconvertible event still appears in the list', (
      tester,
    ) async {
      await _pumpForecast(
        tester,
        accounts: [_account(id: 'a1', code: 'RUB', balance: 1000000)],
        ops: [
          _op(
            id: 'o1',
            title: 'Отель',
            amount: 20000,
            code: 'EUR',
            schedule: Schedule.once,
            startDate: addDays(_today, 3),
          ),
        ],
      );

      expect(find.text('Отель'), findsOneWidget);
      expect(find.text('нет курса'), findsOneWidget);
      // The balance is not silently reduced by an amount nobody can convert.
      expect(find.text(formatMoney(1000000, 'RUB')), findsWidgets);
    });
  });
}
