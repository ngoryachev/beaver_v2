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
import 'package:beaver_v2/presentation/providers/projection_provider.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/providers/scenarios_provider.dart';
import 'package:beaver_v2/presentation/screens/scenarios/scenario_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

/// The scenario editor is the only place exclusions are actually authored, and
/// the invariant it has to keep is the one the whole feature rests on: a
/// scenario stores what it *excludes*, so unchecking a row must produce an
/// exclusion and nothing else — anything created later stays included.
const _userId = 'u1';

final _default = Scenario(
  id: 's-all',
  userId: _userId,
  name: 'Все',
  isDefault: true,
);

const _card = Account(
  id: 'a1',
  userId: _userId,
  name: 'Карта',
  currencyCode: 'RUB',
  balance: 100000,
);

const _savings = Account(
  id: 'a2',
  userId: _userId,
  name: 'Копилка',
  currencyCode: 'RUB',
  balance: 500000,
);

final _rent = PlannedOp(
  id: 'op1',
  userId: _userId,
  title: 'Аренда',
  amount: 800000,
  currencyCode: 'RUB',
  kind: OpKind.expense,
  schedule: Schedule.monthly,
  startDate: DateTime(2026),
);

/// Pumps the editor behind a real router: it calls `context.pop()` after a
/// successful save, which only exists once a GoRouter is in the tree.
Future<ProviderContainer> _pumpEditor(
  WidgetTester tester, {
  String? scenarioId,
  required InMemoryScenariosRepository scenarios,
}) async {
  // Tall enough that the whole form, save button included, is laid out.
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue(_userId),
      accountsRepositoryProvider.overrideWithValue(
        InMemoryAccountsRepository(const [_card, _savings]),
      ),
      plannedOpsRepositoryProvider.overrideWithValue(
        InMemoryPlannedOpsRepository([_rent]),
      ),
      scenariosRepositoryProvider.overrideWithValue(scenarios),
      ratesRepositoryProvider.overrideWithValue(InMemoryRatesRepository()),
      settingsRepositoryProvider.overrideWithValue(
        InMemorySettingsRepository(
          const UserSettings(userId: _userId, baseCurrency: 'RUB'),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/scenarios/edit', extra: scenarioId),
              child: const Text('открыть'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/scenarios/edit',
        builder: (context, state) =>
            ScenarioEditScreen(scenarioId: state.extra as String?),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('ru'),
        supportedLocales: BeaverApp.supportedLocales,
        localizationsDelegates: BeaverApp.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();
  return container;
}

bool _isChecked(WidgetTester tester, String title) => tester
    .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, title))
    .value!;

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('a new scenario', () {
    testWidgets('starts with everything included', (tester) async {
      await _pumpEditor(tester, scenarios: InMemoryScenariosRepository([_default]));

      expect(find.text('Новый сценарий'), findsOneWidget);
      expect(_isChecked(tester, 'Карта'), isTrue);
      expect(_isChecked(tester, 'Копилка'), isTrue);
      expect(_isChecked(tester, 'Аренда'), isTrue);
    });

    testWidgets('stores an unchecked account as an exclusion', (tester) async {
      final repository = InMemoryScenariosRepository([_default]);
      final container = await _pumpEditor(tester, scenarios: repository);

      await tester.enterText(find.byType(TextFormField), 'Без копилки');
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Копилка'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      final stored = (await repository.getAll()).firstWhere(
        (scenario) => !scenario.isDefault,
      );
      expect(stored.name, 'Без копилки');
      expect(stored.disabledAccountIds, {'a2'});
      expect(stored.disabledOpIds, isEmpty);
      // Not marked default: «Все» must stay the only undeletable one.
      expect(stored.isDefault, isFalse);

      // And the exclusion is what the projection actually honours.
      container.read(activeScenarioIdProvider.notifier).state = stored.id;
      expect(container.read(currentTotalProvider).startBalance, 100000);
    });

    testWidgets('stores an unchecked operation as an exclusion', (tester) async {
      final repository = InMemoryScenariosRepository([_default]);
      await _pumpEditor(tester, scenarios: repository);

      await tester.enterText(find.byType(TextFormField), 'Без аренды');
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Аренда'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      final stored = (await repository.getAll()).firstWhere(
        (scenario) => !scenario.isDefault,
      );
      expect(stored.disabledOpIds, {'op1'});
      expect(stored.disabledAccountIds, isEmpty);
    });

    testWidgets('an empty name blocks the save', (tester) async {
      final repository = InMemoryScenariosRepository([_default]);
      await _pumpEditor(tester, scenarios: repository);

      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      expect(find.text('Введите название'), findsOneWidget);
      expect((await repository.getAll()).length, 1);
    });
  });

  group('an existing scenario', () {
    final trip = Scenario(
      id: 's-trip',
      userId: _userId,
      name: 'Поездка',
      disabledAccountIds: const {'a2'},
      disabledOpIds: const {'op1'},
    );

    testWidgets('is prefilled with its exclusions unchecked', (tester) async {
      await _pumpEditor(
        tester,
        scenarioId: trip.id,
        scenarios: InMemoryScenariosRepository([_default, trip]),
      );

      expect(find.text('Сценарий'), findsOneWidget);
      expect(_isChecked(tester, 'Карта'), isTrue);
      expect(_isChecked(tester, 'Копилка'), isFalse);
      expect(_isChecked(tester, 'Аренда'), isFalse);
    });

    testWidgets('re-checking a row removes the exclusion', (tester) async {
      final repository = InMemoryScenariosRepository([_default, trip]);
      await _pumpEditor(tester, scenarioId: trip.id, scenarios: repository);

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Копилка'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      final stored = (await repository.getAll()).firstWhere(
        (scenario) => scenario.id == trip.id,
      );
      expect(stored.disabledAccountIds, isEmpty);
      // The operation the user did not touch keeps its exclusion.
      expect(stored.disabledOpIds, {'op1'});
      // Saving edits the same row rather than adding a second one.
      expect((await repository.getAll()).length, 2);
    });

    testWidgets('a rename keeps the exclusions', (tester) async {
      final repository = InMemoryScenariosRepository([_default, trip]);
      await _pumpEditor(tester, scenarioId: trip.id, scenarios: repository);

      await tester.enterText(find.byType(TextFormField), 'Отпуск');
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      final stored = (await repository.getAll()).firstWhere(
        (scenario) => scenario.id == trip.id,
      );
      expect(stored.name, 'Отпуск');
      expect(stored.disabledAccountIds, {'a2'});
      expect(stored.disabledOpIds, {'op1'});
    });
  });

  group('the default scenario', () {
    testWidgets('keeps its default flag when edited', (tester) async {
      final repository = InMemoryScenariosRepository([_default]);
      await _pumpEditor(
        tester,
        scenarioId: _default.id,
        scenarios: repository,
      );

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Копилка'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      final stored = (await repository.getAll()).single;
      // Losing this flag would leave the user with no undeletable fallback and
      // the notifier would silently create a second «Все» on the next load.
      expect(stored.isDefault, isTrue);
    });
  });
}
