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

/// The editor must not merely survive a stored value its dropdowns do not list
/// — it must keep what the operation actually says. Dropping the link to an
/// archived account would quietly re-point the operation at «Любой», which is a
/// silent data change the user never asked for.
const _userId = 'u1';

const _liveAccount = Account(
  id: 'a2',
  userId: _userId,
  name: 'Карта',
  currencyCode: 'RUB',
  balance: 100000,
);

const _archivedAccount = Account(
  id: 'a1',
  userId: _userId,
  name: 'Старая карта',
  currencyCode: 'RUB',
  balance: 5000,
  archived: true,
);

PlannedOp _op({String? accountId, String currencyCode = 'RUB'}) => PlannedOp(
  id: 'op1',
  userId: _userId,
  title: 'Аренда',
  amount: 100000,
  currencyCode: currencyCode,
  kind: OpKind.expense,
  accountId: accountId,
  schedule: Schedule.monthly,
  startDate: DateTime(2026, 6, 10),
);

Future<InMemoryPlannedOpsRepository> _pumpEditor(
  WidgetTester tester, {
  required List<Account> accounts,
  required PlannedOp op,
}) async {
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final opsRepository = InMemoryPlannedOpsRepository([op]);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/edit'),
            child: const Text('Открыть'),
          ),
        ),
      ),
      GoRoute(
        path: '/edit',
        builder: (context, state) => const OpEditScreen(opId: 'op1'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_userId),
        accountsRepositoryProvider.overrideWithValue(
          InMemoryAccountsRepository(accounts),
        ),
        plannedOpsRepositoryProvider.overrideWithValue(opsRepository),
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
  // Onto the editor via a real push, so saving has somewhere to pop back to —
  // `_submit` finishes with `context.pop()`.
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
  return opsRepository;
}

/// The value a `DropdownButtonFormField<T>` is currently showing.
T? _dropdownValue<T>(WidgetTester tester) => tester
    .widget<DropdownButtonFormField<T>>(find.byType(DropdownButtonFormField<T>))
    .initialValue;

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('an archived account', () {
    testWidgets('stays selected and is marked as archived', (tester) async {
      await _pumpEditor(
        tester,
        accounts: const [_archivedAccount, _liveAccount],
        op: _op(accountId: 'a1'),
      );

      expect(_dropdownValue<String?>(tester), 'a1');
      // Marked, so the user can see why it is not in the normal list.
      expect(find.text('Старая карта (в архиве)'), findsWidgets);
    });

    testWidgets('survives a save instead of being dropped', (tester) async {
      final ops = await _pumpEditor(
        tester,
        accounts: const [_archivedAccount, _liveAccount],
        op: _op(accountId: 'a1'),
      );

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Сохранить'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      expect((await ops.getAll()).single.accountId, 'a1');
    });
  });

  group('an account id matching nothing', () {
    testWidgets('falls back to «Любой»', (tester) async {
      await _pumpEditor(
        tester,
        accounts: const [_liveAccount],
        op: _op(accountId: 'gone'),
      );

      expect(_dropdownValue<String?>(tester), isNull);
    });

    testWidgets('is cleared on save, so the foreign key cannot reject it', (
      tester,
    ) async {
      final ops = await _pumpEditor(
        tester,
        accounts: const [_liveAccount],
        op: _op(accountId: 'gone'),
      );

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Сохранить'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      expect((await ops.getAll()).single.accountId, isNull);
    });
  });

  group('a currency outside the static list', () {
    testWidgets('stays selected', (tester) async {
      await _pumpEditor(
        tester,
        accounts: const [_liveAccount],
        op: _op(currencyCode: 'PLN'),
      );

      expect(_dropdownValue<String>(tester), 'PLN');
    });

    testWidgets('is shown canonically even if stored in another case', (
      tester,
    ) async {
      // `Currency.byCode` upper-cases, so resolving the shown value and the
      // dropdown item separately would mismatch and assert.
      await _pumpEditor(
        tester,
        accounts: const [_liveAccount],
        op: _op(currencyCode: 'pln'),
      );

      expect(tester.takeException(), isNull);
      expect(_dropdownValue<String>(tester), 'PLN');
    });

    testWidgets('survives a save', (tester) async {
      final ops = await _pumpEditor(
        tester,
        accounts: const [_liveAccount],
        op: _op(currencyCode: 'PLN'),
      );

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Сохранить'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      expect((await ops.getAll()).single.currencyCode, 'PLN');
    });
  });
}
