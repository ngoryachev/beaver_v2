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
import 'package:beaver_v2/presentation/providers/accounts_provider.dart';
import 'package:beaver_v2/presentation/providers/ops_provider.dart';
import 'package:beaver_v2/presentation/providers/projection_provider.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/providers/scenarios_provider.dart';
import 'package:beaver_v2/presentation/screens/scenarios/scenarios_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _userId = 'u1';

final _default = Scenario(
  id: 's-all',
  userId: _userId,
  name: 'Все',
  isDefault: true,
);

Account _account(String id, int balance) => Account(
  id: id,
  userId: _userId,
  name: 'Счёт $id',
  currencyCode: 'RUB',
  balance: balance,
);

PlannedOp _op(String id, int amount) => PlannedOp(
  id: id,
  userId: _userId,
  title: 'Операция $id',
  amount: amount,
  currencyCode: 'RUB',
  kind: OpKind.expense,
  schedule: Schedule.daily,
  startDate: DateTime(2020),
);

ProviderContainer _container({
  List<Account> accounts = const [],
  List<PlannedOp> ops = const [],
  List<Scenario> scenarios = const [],
  InMemoryScenariosRepository? scenariosRepository,
  InMemoryAccountsRepository? accountsRepository,
}) {
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue(_userId),
      accountsRepositoryProvider.overrideWithValue(
        accountsRepository ?? InMemoryAccountsRepository(accounts),
      ),
      plannedOpsRepositoryProvider.overrideWithValue(
        InMemoryPlannedOpsRepository(ops),
      ),
      scenariosRepositoryProvider.overrideWithValue(
        scenariosRepository ?? InMemoryScenariosRepository(scenarios),
      ),
      ratesRepositoryProvider.overrideWithValue(InMemoryRatesRepository()),
      settingsRepositoryProvider.overrideWithValue(
        InMemorySettingsRepository(
          const UserSettings(userId: _userId, baseCurrency: 'RUB'),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _warmUp(ProviderContainer container) async {
  await container.read(accountsProvider.future);
  await container.read(opsProvider.future);
  await container.read(scenariosProvider.future);
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('the default scenario', () {
    test('is created on demand when the user has none', () async {
      final repository = InMemoryScenariosRepository();
      final container = _container(scenariosRepository: repository);

      final scenarios = await container.read(scenariosProvider.future);

      expect(scenarios.single.name, defaultScenarioName);
      expect(scenarios.single.isDefault, isTrue);
      // Persisted, not just synthesised in memory.
      expect((await repository.getAll()).single.isDefault, isTrue);
    });

    test('cannot be deleted', () async {
      final repository = InMemoryScenariosRepository([_default]);
      final container = _container(scenariosRepository: repository);
      await container.read(scenariosProvider.future);

      await expectLater(
        container.read(scenariosProvider.notifier).delete(_default.id),
        throwsStateError,
      );
      expect((await repository.getAll()).length, 1);
    });

    test('is what an unknown selection falls back to', () async {
      final container = _container(scenarios: [_default]);
      await container.read(scenariosProvider.future);

      container.read(activeScenarioIdProvider.notifier).state = 'нет такого';

      expect(container.read(activeScenarioProvider)?.id, _default.id);
    });
  });

  group('a scenario excludes without deleting', () {
    test('an excluded account drops out of the total', () async {
      final trip = Scenario(
        id: 's-trip',
        userId: _userId,
        name: 'Без копилки',
        disabledAccountIds: const {'a2'},
      );
      final container = _container(
        accounts: [_account('a1', 100000), _account('a2', 500000)],
        scenarios: [_default, trip],
      );
      await _warmUp(container);

      expect(container.read(currentTotalProvider).startBalance, 600000);

      container.read(activeScenarioIdProvider.notifier).state = trip.id;

      expect(container.read(currentTotalProvider).startBalance, 100000);
      // The account itself is untouched — exclusion is a view, not a deletion.
      expect(container.read(accountsProvider).requireValue.length, 2);
    });

    test('an excluded operation drops out of the forecast', () async {
      final trip = Scenario(
        id: 's-trip',
        userId: _userId,
        name: 'Без кафе',
        disabledOpIds: const {'o1'},
      );
      final container = _container(
        accounts: [_account('a1', 1000000)],
        ops: [_op('o1', 10000)],
        scenarios: [_default, trip],
      );
      await _warmUp(container);

      final target = addDays(dateOnly(DateTime.now()), 10);
      // 11 daily occurrences (today included) of 100 ₽.
      expect(container.read(projectionProvider(target)).endBalance, 890000);

      container.read(activeScenarioIdProvider.notifier).state = trip.id;

      expect(container.read(projectionProvider(target)).endBalance, 1000000);
      expect(container.read(projectionProvider(target)).events, isEmpty);
    });

    test('an account created later is part of every scenario', () async {
      final trip = Scenario(
        id: 's-trip',
        userId: _userId,
        name: 'Без копилки',
        disabledAccountIds: const {'a2'},
      );
      final container = _container(
        accounts: [_account('a1', 100000), _account('a2', 500000)],
        scenarios: [_default, trip],
      );
      await _warmUp(container);
      container.read(activeScenarioIdProvider.notifier).state = trip.id;
      expect(container.read(currentTotalProvider).startBalance, 100000);

      await container
          .read(accountsProvider.notifier)
          .add(name: 'Новый', currencyCode: 'RUB', balance: 250000);

      // Scenarios store exclusions, so anything new is included automatically.
      expect(container.read(currentTotalProvider).startBalance, 350000);
    });

    test('deleting the active scenario falls back to the default', () async {
      final trip = Scenario(
        id: 's-trip',
        userId: _userId,
        name: 'Без копилки',
        disabledAccountIds: const {'a2'},
      );
      final container = _container(
        accounts: [_account('a1', 100000), _account('a2', 500000)],
        scenarios: [_default, trip],
      );
      await _warmUp(container);
      container.read(activeScenarioIdProvider.notifier).state = trip.id;

      await container.read(scenariosProvider.notifier).delete(trip.id);

      expect(container.read(activeScenarioProvider)?.id, _default.id);
      expect(container.read(currentTotalProvider).startBalance, 600000);
    });
  });

  group('ScenariosScreen', () {
    Future<void> pump(WidgetTester tester, List<Scenario> scenarios) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: _container(
            accounts: [_account('a1', 100000)],
            scenarios: scenarios,
          ),
          child: MaterialApp(
            locale: const Locale('ru'),
            supportedLocales: BeaverApp.supportedLocales,
            localizationsDelegates: BeaverApp.localizationsDelegates,
            home: const ScenariosScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers no delete button for the default scenario', (
      tester,
    ) async {
      await pump(tester, [_default]);

      expect(find.text('Все'), findsOneWidget);
      expect(find.text('Учитывает всё'), findsOneWidget);
      expect(find.byTooltip('Удалить'), findsNothing);
      expect(find.byTooltip('Изменить'), findsNothing);
    });

    testWidgets('offers delete and edit for a custom scenario only', (
      tester,
    ) async {
      await pump(tester, [
        _default,
        Scenario(
          id: 's-trip',
          userId: _userId,
          name: 'Поездка',
          disabledAccountIds: const {'a1'},
        ),
      ]);

      expect(find.byTooltip('Удалить'), findsOneWidget);
      expect(find.byTooltip('Изменить'), findsOneWidget);
      expect(
        find.text('Выключено: счетов 1, операций 0'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a row makes it the active scenario', (tester) async {
      final trip = Scenario(id: 's-trip', userId: _userId, name: 'Поездка');
      await pump(tester, [_default, trip]);

      final radios = tester.widgetList<Radio<String>>(find.byType(Radio<String>));
      expect(radios.length, 2);

      await tester.tap(find.text('Поездка'));
      await tester.pumpAndSettle();

      final group = tester.widget<RadioGroup<String>>(
        find.byType(RadioGroup<String>),
      );
      expect(group.groupValue, trip.id);
    });
  });
}
