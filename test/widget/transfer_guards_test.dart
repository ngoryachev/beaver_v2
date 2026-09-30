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

/// Transfer paths the sheet has to refuse or round on its own: the same account
/// on both sides, and a destination whose currency has no minor units at all.
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

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('TransferSheet — the same account on both sides', () {
    testWidgets('is refused instead of doubling or zeroing the balance', (
      tester,
    ) async {
      final repository = await _pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 500000,
          ),
          _account(
            id: 'a2',
            name: 'Наличные',
            currencyCode: 'RUB',
            balance: 100000,
            sortOrder: 1,
          ),
        ],
      );

      await _openTransfer(tester);
      await _pickAccount(tester, isSource: true, name: 'Карта');
      await _pickAccount(tester, isSource: false, name: 'Карта');
      await tester.enterText(find.byType(TextField).first, '1000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Перевести'));
      await tester.pumpAndSettle();

      expect(find.text('Счета должны быть разными'), findsOneWidget);
      final stored = await repository.getAll();
      expect(
        stored.map((account) => account.balance).toList(),
        [500000, 100000],
        reason: 'a refused transfer must not touch any balance',
      );
    });
  });

  group('TransferSheet — a destination without minor units', () {
    testWidgets('credits whole yen, converted from the debited roubles', (
      tester,
    ) async {
      // 1 USD = 100 ₽ = 150 ¥, so 1 000 ₽ is 1 500 ¥ exactly.
      final repository = await _pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 500000,
          ),
          _account(
            id: 'a2',
            name: 'Иены',
            currencyCode: 'JPY',
            balance: 0,
            sortOrder: 1,
          ),
        ],
        rates: [_rate('RUB', 100), _rate('JPY', 150)],
      );

      await _openTransfer(tester);
      await _pickAccount(tester, isSource: true, name: 'Карта');
      await _pickAccount(tester, isSource: false, name: 'Иены');
      await tester.enterText(find.byType(TextField).first, '1000');
      await tester.pumpAndSettle();

      // The credited field is prefilled from the rate, with no fractional part.
      final credited = tester.widget<TextField>(find.byType(TextField).last);
      expect(credited.controller?.text, '1500');

      await tester.tap(find.text('Перевести'));
      await tester.pumpAndSettle();

      final stored = await repository.getAll();
      expect(stored.firstWhere((a) => a.id == 'a1').balance, 400000);
      // Minor units of JPY are whole yen: 1 500, not 150 000.
      expect(stored.firstWhere((a) => a.id == 'a2').balance, 1500);
    });
  });
}
