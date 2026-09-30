import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_scenarios_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/models/scenario.dart';
import 'package:beaver_v2/domain/models/user_settings.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// A half-filled transfer form. Every one of these ends with «Перевести» being
/// pressed on something the sheet cannot turn into two balance changes, and the
/// requirement is the same each time: say what is missing and leave both
/// balances exactly where they were. Writing a partial transfer is the one
/// failure this screen must never have, because nothing in the app can undo it.
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

Future<InMemoryAccountsRepository> _pumpHome(
  WidgetTester tester, {
  required List<Account> accounts,
  List<Rate> rates = const [],
}) async {
  final accountsRepository = InMemoryAccountsRepository(accounts);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_userId),
        accountsRepositoryProvider.overrideWithValue(accountsRepository),
        plannedOpsRepositoryProvider.overrideWithValue(
          InMemoryPlannedOpsRepository(const []),
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
            const UserSettings(userId: _userId, baseCurrency: 'RUB'),
          ),
        ),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return accountsRepository;
}

Future<void> _openTransfer(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Перевод'));
  await tester.pumpAndSettle();
}

Future<void> _pickAccount(
  WidgetTester tester, {
  required bool isSource,
  required String name,
}) async {
  final dropdown = isSource
      ? find.byType(DropdownButtonFormField<String>).first
      : find.byType(DropdownButtonFormField<String>).last;
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(name).last);
  await tester.pumpAndSettle();
}

Future<List<int>> _balances(InMemoryAccountsRepository repository) async {
  final stored = await repository.getAll();
  return stored.map((account) => account.balance).toList();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  final twoRoubleAccounts = [
    _account(id: 'a1', name: 'Карта', currencyCode: 'RUB', balance: 500000),
    _account(
      id: 'a2',
      name: 'Наличные',
      currencyCode: 'RUB',
      balance: 100000,
      sortOrder: 1,
    ),
  ];

  group('TransferSheet — nothing chosen', () {
    testWidgets('asks for both accounts and moves no money', (tester) async {
      final repository = await _pumpHome(tester, accounts: twoRoubleAccounts);
      await _openTransfer(tester);

      await tester.enterText(find.byType(TextField).first, '1000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Перевести'));
      await tester.pumpAndSettle();

      expect(find.text('Выберите оба счёта'), findsOneWidget);
      expect(await _balances(repository), [500000, 100000]);
    });

    testWidgets('asks for both accounts when only the source is set', (
      tester,
    ) async {
      final repository = await _pumpHome(tester, accounts: twoRoubleAccounts);
      await _openTransfer(tester);
      await _pickAccount(tester, isSource: true, name: 'Карта');

      await tester.enterText(find.byType(TextField).first, '1000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Перевести'));
      await tester.pumpAndSettle();

      expect(find.text('Выберите оба счёта'), findsOneWidget);
      expect(await _balances(repository), [500000, 100000]);
    });
  });

  group('TransferSheet — no amount', () {
    testWidgets('an empty debit field is refused', (tester) async {
      final repository = await _pumpHome(tester, accounts: twoRoubleAccounts);
      await _openTransfer(tester);
      await _pickAccount(tester, isSource: true, name: 'Карта');
      await _pickAccount(tester, isSource: false, name: 'Наличные');

      await tester.tap(find.text('Перевести'));
      await tester.pumpAndSettle();

      expect(find.text('Введите сумму списания'), findsOneWidget);
      expect(await _balances(repository), [500000, 100000]);
    });

    testWidgets('zero is refused: it is not a transfer', (tester) async {
      final repository = await _pumpHome(tester, accounts: twoRoubleAccounts);
      await _openTransfer(tester);
      await _pickAccount(tester, isSource: true, name: 'Карта');
      await _pickAccount(tester, isSource: false, name: 'Наличные');

      await tester.enterText(find.byType(TextField).first, '0');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Перевести'));
      await tester.pumpAndSettle();

      expect(find.text('Введите сумму списания'), findsOneWidget);
      expect(await _balances(repository), [500000, 100000]);
    });

    testWidgets('a negative amount cannot be turned into a reverse transfer', (
      tester,
    ) async {
      final repository = await _pumpHome(tester, accounts: twoRoubleAccounts);
      await _openTransfer(tester);
      await _pickAccount(tester, isSource: true, name: 'Карта');
      await _pickAccount(tester, isSource: false, name: 'Наличные');

      await tester.enterText(find.byType(TextField).first, '-1000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Перевести'));
      await tester.pumpAndSettle();

      expect(find.text('Введите сумму списания'), findsOneWidget);
      expect(await _balances(repository), [500000, 100000]);
    });
  });

  group('TransferSheet — cross-currency with no rate', () {
    // Only the rouble rate is stored, so RUB → EUR cannot be prefilled and the
    // credited field stays empty. Pressing «Перевести» then has to stop: the
    // debited side alone would take money out of one account and put it
    // nowhere.
    final crossCurrency = [
      _account(id: 'a1', name: 'Карта', currencyCode: 'RUB', balance: 500000),
      _account(
        id: 'a2',
        name: 'Евро',
        currencyCode: 'EUR',
        balance: 20000,
        sortOrder: 1,
      ),
    ];

    testWidgets('leaves the credited field empty and refuses the transfer', (
      tester,
    ) async {
      final repository = await _pumpHome(
        tester,
        accounts: crossCurrency,
        rates: [_rate('RUB', 100)],
      );
      await _openTransfer(tester);
      await _pickAccount(tester, isSource: true, name: 'Карта');
      await _pickAccount(tester, isSource: false, name: 'Евро');

      await tester.enterText(find.byType(TextField).first, '1000');
      await tester.pumpAndSettle();

      final credited = tester.widget<TextField>(find.byType(TextField).last);
      expect(
        credited.controller?.text,
        '',
        reason: 'with no rate there is nothing to prefill — and 0 would be a lie',
      );

      await tester.tap(find.text('Перевести'));
      await tester.pumpAndSettle();

      expect(find.text('Введите сумму зачисления'), findsOneWidget);
      expect(await _balances(repository), [500000, 20000]);
    });

    testWidgets('a hand-typed credited amount still goes through', (
      tester,
    ) async {
      final repository = await _pumpHome(
        tester,
        accounts: crossCurrency,
        rates: [_rate('RUB', 100)],
      );
      await _openTransfer(tester);
      await _pickAccount(tester, isSource: true, name: 'Карта');
      await _pickAccount(tester, isSource: false, name: 'Евро');

      await tester.enterText(find.byType(TextField).first, '1000');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '9,50');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Перевести'));
      await tester.pumpAndSettle();

      expect(await _balances(repository), [400000, 20950]);
    });
  });

  group('TransferSheet — fewer than two accounts', () {
    testWidgets('says so instead of offering an unusable form', (tester) async {
      await _pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 500000,
          ),
        ],
      );
      await _openTransfer(tester);

      expect(find.text('Для перевода нужно хотя бы два счёта'), findsOneWidget);
      expect(find.text('Перевести'), findsNothing);
    });

    testWidgets('an archived second account does not count', (tester) async {
      await _pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 500000,
          ),
          Account(
            id: 'a2',
            userId: _userId,
            name: 'Старый',
            currencyCode: 'RUB',
            balance: 100000,
            archived: true,
            sortOrder: 1,
          ),
        ],
      );
      await _openTransfer(tester);

      expect(find.text('Для перевода нужно хотя бы два счёта'), findsOneWidget);
    });
  });
}
