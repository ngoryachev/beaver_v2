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
import 'package:beaver_v2/presentation/screens/home/home_screen.dart';
import 'package:beaver_v2/presentation/screens/ops/op_edit_screen.dart';
import 'package:beaver_v2/presentation/screens/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Archiving a card is a normal, one-tap action in settings, and an operation
/// may well be tied to it («Аренда» paid from the card being retired). These
/// tests walk that whole path through the real screens and the real providers,
/// with only the repositories swapped for in-memory ones — nothing here
/// constructs a state the UI could not produce by itself.
const _userId = 'u1';

final _card = Account(
  id: 'a1',
  userId: _userId,
  name: 'Старая карта',
  currencyCode: 'RUB',
  balance: 500000,
);

final _rent = PlannedOp(
  id: 'op1',
  userId: _userId,
  title: 'Аренда',
  amount: 100000,
  currencyCode: 'RUB',
  kind: OpKind.expense,
  accountId: 'a1',
  schedule: Schedule.monthly,
  startDate: DateTime(2026, 6, 10),
);

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue(_userId),
      accountsRepositoryProvider.overrideWithValue(
        InMemoryAccountsRepository([_card]),
      ),
      plannedOpsRepositoryProvider.overrideWithValue(
        InMemoryPlannedOpsRepository([_rent]),
      ),
      scenariosRepositoryProvider.overrideWithValue(
        InMemoryScenariosRepository([
          Scenario(id: 's1', userId: _userId, name: 'Все', isDefault: true),
        ]),
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

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget screen,
) async {
  // Tall enough that a whole form is laid out without scrolling.
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: BeaverApp.supportedLocales,
        localizationsDelegates: BeaverApp.localizationsDelegates,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('the operations section survives its account being archived', (
    tester,
  ) async {
    final container = _container();
    await _pump(tester, container, const SettingsScreen());
    await tester.tap(find.widgetWithText(TextButton, 'В архив'));
    await tester.pumpAndSettle();

    await _pump(tester, container, const HomeScreen());
    // «Аренда» has no category, so it sits under «Прочее» — collapsed by
    // default, like every group.
    await tester.tap(find.text('Прочее'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Аренда'), findsOneWidget);
  });

  testWidgets('an operation can still be opened after its account is archived', (
    tester,
  ) async {
    final container = _container();

    // Step one: retire the card from settings — one tap, no special state.
    await _pump(tester, container, const SettingsScreen());
    expect(find.widgetWithText(TextButton, 'В архив'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'В архив'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Вернуть'), findsOneWidget);

    // Step two: open the operation that pointed at it, exactly as tapping the
    // row in the «Операции» section does.
    await _pump(tester, container, const OpEditScreen(opId: 'op1'));

    expect(tester.takeException(), isNull);
    expect(find.text('Аренда'), findsWidgets);
  });
}
