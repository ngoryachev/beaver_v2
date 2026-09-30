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
import 'package:intl/date_symbol_data_local.dart';

/// The «Счёт» and «Валюта» dropdowns of the operation editor are built from lists
/// that do not necessarily contain the value the stored operation carries:
/// «Счёт» lists only non-archived accounts, «Валюта» only [Currency.all].
/// `DropdownButtonFormField` asserts that its value is among the items, so an
/// operation pointing at anything else cannot be opened at all.
const _userId = 'u1';

final _liveAccount = Account(
  id: 'a2',
  userId: _userId,
  name: 'Карта',
  currencyCode: 'RUB',
  balance: 100000,
);

Future<void> _pumpEditor(
  WidgetTester tester, {
  required List<Account> accounts,
  required List<PlannedOp> ops,
}) async {
  // A tall surface so the whole form is laid out, including the dropdowns near
  // the bottom of the ListView.
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_userId),
        accountsRepositoryProvider.overrideWithValue(
          InMemoryAccountsRepository(accounts),
        ),
        plannedOpsRepositoryProvider.overrideWithValue(
          InMemoryPlannedOpsRepository(ops),
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
        home: const OpEditScreen(opId: 'op1'),
        locale: const Locale('ru'),
        supportedLocales: BeaverApp.supportedLocales,
        localizationsDelegates: BeaverApp.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('an operation tied to an archived account still opens', (
    tester,
  ) async {
    // Reachable entirely from the UI: create the operation on «Старая карта»,
    // archive that account in settings, then tap the operation in the list.
    await _pumpEditor(
      tester,
      accounts: [
        Account(
          id: 'a1',
          userId: _userId,
          name: 'Старая карта',
          currencyCode: 'RUB',
          balance: 5000,
          archived: true,
        ),
        _liveAccount,
      ],
      ops: [
        PlannedOp(
          id: 'op1',
          userId: _userId,
          title: 'Аренда',
          amount: 100000,
          currencyCode: 'RUB',
          kind: OpKind.expense,
          accountId: 'a1',
          schedule: Schedule.monthly,
          startDate: DateTime(2026, 6, 10),
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Аренда'), findsWidgets);
  });

  testWidgets('an operation in a currency outside the static list still opens', (
    tester,
  ) async {
    // `Currency.byCode` deliberately tolerates an unknown code «so a row written
    // by a newer build never crashes an older one» — the editor must tolerate it
    // too.
    await _pumpEditor(
      tester,
      accounts: [_liveAccount],
      ops: [
        PlannedOp(
          id: 'op1',
          userId: _userId,
          title: 'Аренда',
          amount: 100000,
          currencyCode: 'PLN',
          kind: OpKind.expense,
          schedule: Schedule.monthly,
          startDate: DateTime(2026, 6, 10),
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Аренда'), findsWidgets);
  });
}
