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
import 'package:beaver_v2/presentation/screens/ops/ops_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _userId = 'u1';

PlannedOp _op({
  required String id,
  required String title,
  required int amount,
  required OpCategory category,
  OpKind kind = OpKind.expense,
  Schedule schedule = Schedule.monthly,
  bool enabled = true,
}) => PlannedOp(
  id: id,
  userId: _userId,
  title: title,
  amount: amount,
  currencyCode: 'RUB',
  kind: kind,
  category: category,
  schedule: schedule,
  startDate: DateTime(2026, 9, 1),
  enabled: enabled,
);

Future<InMemoryPlannedOpsRepository> _pumpOps(
  WidgetTester tester,
  List<PlannedOp> ops,
) async {
  final repository = InMemoryPlannedOpsRepository(ops);

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
      child: const MaterialApp(home: OpsListScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('an empty list explains what to do', (tester) async {
    await _pumpOps(tester, const []);
    expect(find.textContaining('Пока нет операций'), findsOneWidget);
  });

  testWidgets('operations are grouped by category in enum order', (
    tester,
  ) async {
    await _pumpOps(tester, [
      _op(
        id: 'o1',
        title: 'Зарплата',
        amount: 20000000,
        category: OpCategory.salary,
        kind: OpKind.income,
      ),
      _op(
        id: 'o2',
        title: 'Продукты',
        amount: 1500000,
        category: OpCategory.food,
      ),
      _op(id: 'o3', title: 'Кафе', amount: 300000, category: OpCategory.food),
    ]);

    // «Еда» is declared before «Зарплата» in OpCategory, so it must come first
    // whatever order the repository returned the rows in.
    final foodY = tester.getTopLeft(find.text('Еда')).dy;
    final salaryY = tester.getTopLeft(find.text('Зарплата').first).dy;
    expect(foodY, lessThan(salaryY));

    // Both food operations sit under the single «Еда» heading.
    expect(find.text('Еда'), findsOneWidget);
    expect(find.text('Продукты'), findsOneWidget);
    expect(find.text('Кафе'), findsOneWidget);
  });

  testWidgets('the switch turns an operation off and stores it', (
    tester,
  ) async {
    final repository = await _pumpOps(tester, [
      _op(
        id: 'o1',
        title: 'Продукты',
        amount: 1500000,
        category: OpCategory.food,
      ),
    ]);

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    final stored = await repository.getAll();
    expect(stored.single.enabled, isFalse);
    // Turning an operation off must not touch anything else about it.
    expect(stored.single.amount, 1500000);
  });

  testWidgets('a disabled operation is still listed', (tester) async {
    await _pumpOps(tester, [
      _op(
        id: 'o1',
        title: 'Подписка',
        amount: 99900,
        category: OpCategory.services,
        enabled: false,
      ),
    ]);

    expect(find.text('Подписка'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  group('swipe to delete', () {
    testWidgets('asks first, then removes the operation', (tester) async {
      final repository = await _pumpOps(tester, [
        _op(
          id: 'o1',
          title: 'Продукты',
          amount: 1500000,
          category: OpCategory.food,
        ),
        _op(
          id: 'o2',
          title: 'Кафе',
          amount: 300000,
          category: OpCategory.food,
        ),
      ]);

      await tester.drag(find.text('Кафе'), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.text('Удалить операцию?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();

      final stored = await repository.getAll();
      expect(stored.map((op) => op.id), ['o1']);
      expect(find.text('Кафе'), findsNothing);
      expect(find.text('Продукты'), findsOneWidget);
    });

    testWidgets('cancelling keeps the operation', (tester) async {
      final repository = await _pumpOps(tester, [
        _op(
          id: 'o1',
          title: 'Продукты',
          amount: 1500000,
          category: OpCategory.food,
        ),
      ]);

      await tester.drag(find.text('Продукты'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
      await tester.pumpAndSettle();

      expect((await repository.getAll()).length, 1);
      expect(find.text('Продукты'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
