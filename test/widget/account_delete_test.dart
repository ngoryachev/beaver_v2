import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_scenarios_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/models/scenario.dart';
import 'package:beaver_v2/domain/models/user_settings.dart';
import 'package:beaver_v2/presentation/format/money_format.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Deleting an account is the one destructive action on the home screen: the
/// balance goes with it, and the planned operations pointing at it are detached
/// rather than removed (`ON DELETE SET NULL` in the schema).
const _userId = 'u1';

Account _account({
  required String id,
  required String name,
  required String currencyCode,
  required int balance,
  int sortOrder = 0,
}) => Account(
  id: id,
  userId: _userId,
  name: name,
  currencyCode: currencyCode,
  balance: balance,
  sortOrder: sortOrder,
);

Rate _rate(String code, double perUsd) => Rate(
  userId: _userId,
  code: code,
  ratePerUsd: perUsd,
  source: RateSource.auto,
  updatedAt: DateTime.now().toUtc(),
);

String _totalText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('home-total'))).data!;

String _digitsOf(String text) => text.replaceAll(RegExp(r'[^\d,-]'), '');

Future<InMemoryAccountsRepository> _pumpHome(
  WidgetTester tester, {
  required List<Account> accounts,
  List<PlannedOp> ops = const [],
  List<Rate> rates = const [],
  String baseCurrency = 'RUB',
}) async {
  final repository = InMemoryAccountsRepository(accounts);
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_userId),
        accountsRepositoryProvider.overrideWithValue(repository),
        plannedOpsRepositoryProvider.overrideWithValue(
          InMemoryPlannedOpsRepository(ops),
        ),
        scenariosRepositoryProvider.overrideWithValue(
          InMemoryScenariosRepository([
            Scenario(id: 's1', userId: _userId, name: 'Все', isDefault: true),
          ]),
        ),
        ratesRepositoryProvider.overrideWithValue(
          InMemoryRatesRepository(rates),
        ),
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(
            UserSettings(userId: _userId, baseCurrency: baseCurrency),
          ),
        ),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _swipe(WidgetTester tester, String name) async {
  await tester.drag(find.text(name), const Offset(-600, 0));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('the dialog names the balance and what happens to operations', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      accounts: [
        _account(id: 'a1', name: 'Карта', currencyCode: 'RUB', balance: 100000),
      ],
    );

    await _swipe(tester, 'Карта');

    expect(find.text('Удалить счёт?'), findsOneWidget);
    expect(
      find.textContaining(formatMoney(100000, 'RUB')),
      findsWidgets,
      reason: 'the balance about to disappear has to be in the dialog',
    );
    expect(find.textContaining('потеряют привязку'), findsOneWidget);
  });

  testWidgets('cancelling keeps the account', (tester) async {
    final repository = await _pumpHome(
      tester,
      accounts: [
        _account(id: 'a1', name: 'Карта', currencyCode: 'RUB', balance: 100000),
      ],
    );

    await _swipe(tester, 'Карта');
    await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
    await tester.pumpAndSettle();

    expect((await repository.getAll()).single.id, 'a1');
    expect(find.text('Карта'), findsOneWidget);
    expect(_digitsOf(_totalText(tester)), '1000,00');
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirming deletes the account and drops it from the total', (
    tester,
  ) async {
    final repository = await _pumpHome(
      tester,
      accounts: [
        _account(id: 'a1', name: 'Карта', currencyCode: 'RUB', balance: 100000),
        _account(
          id: 'a2',
          name: 'Копилка',
          currencyCode: 'RUB',
          balance: 500000,
          sortOrder: 1,
        ),
      ],
    );
    expect(_digitsOf(_totalText(tester)), '6000,00');

    await _swipe(tester, 'Копилка');
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();

    expect((await repository.getAll()).map((a) => a.id), ['a1']);
    expect(find.text('Копилка'), findsNothing);
    expect(_digitsOf(_totalText(tester)), '1000,00');
  });

  testWidgets('an operation tied to the deleted account stays in the list', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      accounts: [
        _account(id: 'a1', name: 'Карта', currencyCode: 'RUB', balance: 100000),
      ],
      ops: [
        PlannedOp(
          id: 'op1',
          userId: _userId,
          title: 'Аренда',
          amount: 5000000,
          currencyCode: 'RUB',
          kind: OpKind.expense,
          accountId: 'a1',
          schedule: Schedule.monthly,
          startDate: DateTime(2026, 6, 10),
        ),
      ],
    );

    await _swipe(tester, 'Карта');
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Пока нет счетов'), findsOneWidget);
    // The in-memory repository mirrors `ON DELETE SET NULL`: the operation is
    // still there, it just points at no account any more.
    await tester.tap(find.text('Прочее'));
    await tester.pumpAndSettle();
    expect(find.text('Аренда'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting the last account of the base currency keeps the total', (
    tester,
  ) async {
    // The base currency is RUB and the only RUB account is the one being
    // deleted: `normalizeBaseCurrency` has to move the total to EUR instead of
    // leaving it reported in a currency no account holds.
    await _pumpHome(
      tester,
      accounts: [
        _account(id: 'a1', name: 'Рубли', currencyCode: 'RUB', balance: 90000),
        _account(
          id: 'a2',
          name: 'Евро',
          currencyCode: 'EUR',
          balance: 10000,
          sortOrder: 1,
        ),
      ],
      rates: [_rate('RUB', 90), _rate('EUR', 0.9)],
    );
    expect(_totalText(tester), contains('₽'));

    await _swipe(tester, 'Рубли');
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();

    expect(_totalText(tester), contains('€'));
    expect(_digitsOf(_totalText(tester)), '100,00');
    expect(find.textContaining('Без курса'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
