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
import 'package:beaver_v2/presentation/screens/ops/op_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

const _userId = 'u1';

final _existing = PlannedOp(
  id: 'op1',
  userId: _userId,
  title: 'Аренда',
  amount: 8500000,
  currencyCode: 'RUB',
  kind: OpKind.expense,
  category: OpCategory.services,
  schedule: Schedule.monthly,
  startDate: DateTime(2026, 6, 10),
  endDate: DateTime(2027, 6, 10),
);

/// Pumps the editor behind a real router: the screen calls `context.pop()` after
/// a successful save, which only exists once a GoRouter is in the tree.
Future<InMemoryPlannedOpsRepository> _pumpEditor(
  WidgetTester tester, {
  String? opId,
  List<PlannedOp> ops = const [],
}) async {
  final repository = InMemoryPlannedOpsRepository(ops);
  // A tall surface so the whole form — including the save button at the bottom
  // of the ListView — is laid out; a lazy list would not build it otherwise.
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/ops/edit', extra: opId),
              child: const Text('открыть'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/ops/edit',
        builder: (context, state) => OpEditScreen(opId: state.extra as String?),
      ),
    ],
  );

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
        plannedOpsRepositoryProvider.overrideWithValue(repository),
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
  return repository;
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('a new operation', () {
    testWidgets('is stored with the typed title and amount', (tester) async {
      final repository = await _pumpEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'),
        '  Продукты  ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Сумма'),
        '1 234,56',
      );
      await _save(tester);

      final stored = await repository.getAll();
      expect(stored.length, 1);
      // Trimmed title, amount in minor units, and the default schedule.
      expect(stored.single.title, 'Продукты');
      expect(stored.single.amount, 123456);
      expect(stored.single.kind, OpKind.expense);
      expect(stored.single.schedule, Schedule.monthly);
      expect(stored.single.enabled, isTrue);
      // A successful save leaves the editor.
      expect(find.text('Новая операция'), findsNothing);
    });

    testWidgets('an empty title blocks the save', (tester) async {
      final repository = await _pumpEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Сумма'),
        '100',
      );
      await _save(tester);

      expect(find.text('Введите название'), findsOneWidget);
      expect(await repository.getAll(), isEmpty);
    });

    testWidgets('a zero amount blocks the save', (tester) async {
      final repository = await _pumpEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'),
        'Ноль',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Сумма'), '0');
      await _save(tester);

      expect(find.text('Сумма больше нуля'), findsOneWidget);
      expect(await repository.getAll(), isEmpty);
    });

    testWidgets('a non-numeric amount blocks the save', (tester) async {
      final repository = await _pumpEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'),
        'Мусор',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Сумма'),
        'абв',
      );
      await _save(tester);

      expect(find.text('Введите сумму'), findsOneWidget);
      expect(await repository.getAll(), isEmpty);
    });

    testWidgets('income is saved as income, not as a negative amount', (
      tester,
    ) async {
      final repository = await _pumpEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'),
        'Зарплата',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Сумма'),
        '200000',
      );
      await tester.tap(find.text('Доход'));
      await tester.pumpAndSettle();
      await _save(tester);

      final stored = await repository.getAll();
      // `amount > 0` is a database CHECK: the sign must live in `kind` only.
      expect(stored.single.kind, OpKind.income);
      expect(stored.single.amount, 20000000);
      expect(stored.single.signedAmount, 20000000);
    });
  });

  group('an existing operation', () {
    testWidgets('is prefilled and keeps its untouched fields', (tester) async {
      final repository = await _pumpEditor(
        tester,
        opId: 'op1',
        ops: [_existing],
      );

      expect(find.text('Аренда'), findsOneWidget);
      expect(find.text('85000'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'),
        'Аренда квартиры',
      );
      await _save(tester);

      final stored = await repository.getAll();
      expect(stored.length, 1, reason: 'editing must not create a second row');
      expect(stored.single.id, 'op1');
      expect(stored.single.title, 'Аренда квартиры');
      expect(stored.single.amount, 8500000);
      expect(stored.single.category, OpCategory.services);
      expect(stored.single.startDate, DateTime(2026, 6, 10));
      expect(stored.single.endDate, DateTime(2027, 6, 10));
    });

    testWidgets('«Убрать окончание» clears the end date', (tester) async {
      final repository = await _pumpEditor(
        tester,
        opId: 'op1',
        ops: [_existing],
      );

      final clear = find.byTooltip('Убрать окончание');
      await tester.tap(clear);
      await tester.pumpAndSettle();

      expect(find.text('Без ограничения'), findsOneWidget);
      await _save(tester);
      expect((await repository.getAll()).single.endDate, isNull);
    });

    testWidgets('the forecast switch is stored', (tester) async {
      final repository = await _pumpEditor(
        tester,
        opId: 'op1',
        ops: [_existing],
      );

      final toggle = find.byType(SwitchListTile);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await _save(tester);

      expect((await repository.getAll()).single.enabled, isFalse);
    });
  });
}
