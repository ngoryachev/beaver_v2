import 'package:beaver_v2/app.dart';
import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_scenarios_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/models/scenario.dart';
import 'package:beaver_v2/domain/models/user_settings.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/screens/forecast/forecast_screen.dart';
import 'package:beaver_v2/presentation/screens/ops/op_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _userId = 'u1';

final _op = PlannedOp(
  id: 'op1',
  userId: _userId,
  title: 'Аренда',
  amount: 8500000,
  currencyCode: 'RUB',
  kind: OpKind.expense,
  schedule: Schedule.monthly,
  startDate: DateTime(2026, 6, 10),
);

/// Mirrors `BeaverApp`'s localization setup so the pickers are exercised under
/// the same delegates the real app installs.
Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_userId),
        accountsRepositoryProvider.overrideWithValue(
          InMemoryAccountsRepository(const [
            Account(
              id: 'a1',
              userId: _userId,
              name: 'Карта',
              currencyCode: 'RUB',
              balance: 100000,
            ),
          ]),
        ),
        plannedOpsRepositoryProvider.overrideWithValue(
          InMemoryPlannedOpsRepository([_op]),
        ),
        scenariosRepositoryProvider.overrideWithValue(
          InMemoryScenariosRepository([
            Scenario(id: 's1', userId: _userId, name: 'Все', isDefault: true),
          ]),
        ),
        ratesRepositoryProvider.overrideWithValue(
          InMemoryRatesRepository(const []),
        ),
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(
            const UserSettings(userId: _userId, baseCurrency: 'RUB'),
          ),
        ),
      ],
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

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('the app installs Russian Material localizations', () {
    test('ru is a supported locale', () {
      expect(BeaverApp.supportedLocales.first, const Locale('ru'));
    });

    testWidgets('the delegates the app installs resolve Russian', (
      tester,
    ) async {
      // Asserts on `BeaverApp`'s own configuration, so dropping a delegate from
      // app.dart fails here rather than at runtime with
      // «No MaterialLocalizations found».
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: BeaverApp.supportedLocales,
          localizationsDelegates: BeaverApp.localizationsDelegates,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      final context = tester.element(find.byType(Scaffold));
      expect(MaterialLocalizations.of(context).cancelButtonLabel, 'Отмена');
      expect(MaterialLocalizations.of(context).okButtonLabel, 'ОК');
    });
  });

  group('forecast «Другая дата»', () {
    testWidgets('opens the date picker instead of throwing', (tester) async {
      await _pump(tester, const ForecastScreen());

      await tester.tap(find.text('Другая дата'));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('operation dates', () {
    testWidgets('the start-date picker opens', (tester) async {
      await _pump(tester, const OpEditScreen(opId: 'op1'));

      await tester.ensureVisible(find.text('Начало'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Начало'));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the end-date picker cannot go before the start date', (
      tester,
    ) async {
      await _pump(tester, const OpEditScreen(opId: 'op1'));

      await tester.ensureVisible(find.text('Окончание'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Окончание'));
      await tester.pumpAndSettle();

      final dialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      // The database enforces `end_date >= start_date`; the picker must not let
      // the user aim at a date it would reject.
      expect(dialog.firstDate, _op.startDate);
    });
  });
}
