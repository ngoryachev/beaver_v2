import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_scenarios_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/scenario.dart';
import 'package:beaver_v2/domain/models/user_settings.dart';
import 'package:beaver_v2/presentation/providers/accounts_provider.dart';
import 'package:beaver_v2/presentation/providers/projection_provider.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/providers/scenarios_provider.dart';
import 'package:beaver_v2/presentation/screens/scenarios/scenarios_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Deleting the scenario the user is currently looking at: the selection has to
/// fall back to «Все», and the totals have to stop hiding what that scenario
/// excluded.
const _userId = 'u1';

final _default = Scenario(
  id: 's-all',
  userId: _userId,
  name: 'Все',
  isDefault: true,
);

final _trip = Scenario(
  id: 's-trip',
  userId: _userId,
  name: 'Без копилки',
  disabledAccountIds: const {'a2'},
);

Account _account(String id, int balance) => Account(
  id: id,
  userId: _userId,
  name: 'Счёт $id',
  currencyCode: 'RUB',
  balance: balance,
);

List<Override> _overrides(InMemoryScenariosRepository scenarios) => [
  currentUserIdProvider.overrideWithValue(_userId),
  accountsRepositoryProvider.overrideWithValue(
    InMemoryAccountsRepository([_account('a1', 100000), _account('a2', 500000)]),
  ),
  plannedOpsRepositoryProvider.overrideWithValue(
    InMemoryPlannedOpsRepository(const []),
  ),
  scenariosRepositoryProvider.overrideWithValue(scenarios),
  ratesRepositoryProvider.overrideWithValue(InMemoryRatesRepository()),
  settingsRepositoryProvider.overrideWithValue(
    InMemorySettingsRepository(
      const UserSettings(userId: _userId, baseCurrency: 'RUB'),
    ),
  ),
];

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('deleting the active scenario', () {
    test('falls back to the default and restores the excluded account', () async {
      final repository = InMemoryScenariosRepository([_default, _trip]);
      final container = ProviderContainer(overrides: _overrides(repository));
      addTearDown(container.dispose);

      await container.read(accountsProvider.future);
      await container.read(scenariosProvider.future);
      container.read(activeScenarioIdProvider.notifier).state = _trip.id;
      expect(container.read(currentTotalProvider).startBalance, 100000);

      await container.read(scenariosProvider.notifier).delete(_trip.id);

      expect(container.read(activeScenarioProvider)?.id, _default.id);
      expect(
        container.read(currentTotalProvider).startBalance,
        600000,
        reason: 'the excluded account counts again once the scenario is gone',
      );
      expect((await repository.getAll()).single.id, _default.id);
    });

    testWidgets('removes the row and leaves the default selected', (
      tester,
    ) async {
      final repository = InMemoryScenariosRepository([_default, _trip]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(repository),
          child: const MaterialApp(home: ScenariosScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_trip.name));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();

      expect(find.text(_trip.name), findsNothing);
      expect(find.text('Все'), findsOneWidget);
      final radio = tester.widget<Radio<String>>(find.byType(Radio<String>));
      expect(radio.value, _default.id);
    });
  });
}
