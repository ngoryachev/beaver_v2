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

/// Deleting from the editor, so removing an operation does not depend on
/// discovering the swipe gesture in the list.
const _userId = 'u1';

final _existing = PlannedOp(
  id: 'op1',
  userId: _userId,
  title: 'Аренда',
  amount: 8500000,
  currencyCode: 'RUB',
  kind: OpKind.expense,
  category: OpCategory.housing,
  schedule: Schedule.monthly,
  startDate: DateTime(2026, 6, 10),
);

Future<InMemoryPlannedOpsRepository> _pumpEditor(
  WidgetTester tester, {
  String? opId,
  List<PlannedOp> ops = const [],
}) async {
  final repository = InMemoryPlannedOpsRepository(ops);
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

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('a new operation has nothing to delete', (tester) async {
    await _pumpEditor(tester);

    expect(find.text('Новая операция'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('cancelling the dialog keeps the operation and the screen', (
    tester,
  ) async {
    final repository = await _pumpEditor(
      tester,
      opId: 'op1',
      ops: [_existing],
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Удалить операцию?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
    await tester.pumpAndSettle();

    expect((await repository.getAll()).single.id, 'op1');
    expect(find.byType(OpEditScreen), findsOneWidget);
  });

  testWidgets('confirming deletes the row and closes the editor', (
    tester,
  ) async {
    final repository = await _pumpEditor(
      tester,
      opId: 'op1',
      ops: [_existing],
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();

    expect(await repository.getAll(), isEmpty);
    // Back on the screen that opened the editor.
    expect(find.byType(OpEditScreen), findsNothing);
    expect(find.text('открыть'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
