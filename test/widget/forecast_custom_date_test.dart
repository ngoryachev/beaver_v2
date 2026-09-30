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
import 'package:beaver_v2/domain/projection/occurrences.dart';
import 'package:beaver_v2/presentation/format/money_format.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/screens/forecast/forecast_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// «Другая дата» is the only horizon the user types; the existing test stops at
/// the picker opening, so this one actually picks a date and checks the forecast
/// moves with it.
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

Future<void> _pumpForecast(WidgetTester tester) async {
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
              // 10 000 ₽: enough to stay positive over the horizons used here.
              balance: 1000000,
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
        home: const ForecastScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('forecast «Другая дата»', () {
    testWidgets('a typed date becomes the horizon and moves the total', (
      tester,
    ) async {
      await _pumpForecast(tester);

      // +30 дней is the default: today plus 30 occurrences of 100 ₽.
      expect(find.text(formatDate(addDays(_today, 30))), findsOneWidget);

      final target = addDays(_today, 45);
      await tester.tap(find.text('Другая дата'));
      await tester.pumpAndSettle();
      // The calendar grid depends on today's date; the input mode does not.
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), formatDate(target));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ОК'));
      await tester.pumpAndSettle();

      // The chip and the summary tile both name the chosen date.
      expect(find.text(formatDate(target)), findsNWidgets(2));
      // 10 000 ₽ − 46 × 100 ₽ (today included) = 5 400 ₽. A monotonically
      // falling balance ends at its own minimum, so both tiles show it.
      expect(
        find.text(formatMoney(1000000 - 46 * 10000, 'RUB')),
        findsWidgets,
      );
      // The old horizon is gone rather than lingering next to the new one.
      expect(find.text(formatMoney(1000000 - 31 * 10000, 'RUB')), findsNothing);
      expect(find.text(formatDate(addDays(_today, 30))), findsNothing);
    });
  });
}
