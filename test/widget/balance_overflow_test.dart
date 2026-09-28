import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_scenarios_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/scenario.dart';
import 'package:beaver_v2/domain/models/user_settings.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// The keypad puts no ceiling on how many digits go into a balance, so whatever
/// `Money.tryParse` makes of a long number is what gets saved. This is the same
/// defect as `test/domain/money_overflow_test.dart`, seen from the screen the
/// user actually touches.
const _userId = 'u1';

Future<InMemoryAccountsRepository> _pumpHome(WidgetTester tester) async {
  final accounts = InMemoryAccountsRepository([
    Account(
      id: 'a1',
      userId: _userId,
      name: 'Карта',
      currencyCode: 'RUB',
      balance: 100000,
    ),
  ]);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_userId),
        accountsRepositoryProvider.overrideWithValue(accounts),
        plannedOpsRepositoryProvider.overrideWithValue(
          InMemoryPlannedOpsRepository(),
        ),
        scenariosRepositoryProvider.overrideWithValue(
          InMemoryScenariosRepository([
            Scenario(id: 's1', userId: _userId, name: 'Все', isDefault: true),
          ]),
        ),
        ratesRepositoryProvider.overrideWithValue(InMemoryRatesRepository()),
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(
            UserSettings(userId: _userId, baseCurrency: 'RUB'),
          ),
        ),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return accounts;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('a long typed balance is never stored as a negative one', (
    tester,
  ) async {
    final repository = await _pumpHome(tester);

    await tester.tap(find.text('Карта'));
    await tester.pumpAndSettle();

    // Seventeen nines: a fat-fingered or pasted amount, nothing exotic.
    for (var i = 0; i < 17; i++) {
      await tester.tap(find.widgetWithText(OutlinedButton, '9'));
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    final stored = (await repository.getAll()).single.balance;
    expect(
      stored,
      greaterThan(0),
      reason: 'typing a positive amount must not produce a negative balance',
    );
  });
}
