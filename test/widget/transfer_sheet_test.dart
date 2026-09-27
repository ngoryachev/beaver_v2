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

  group('TransferSheet — changing the destination after a manual edit', () {
    testWidgets('a same-currency transfer credits exactly what it debits', (
      tester,
    ) async {
      final repository = await _pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 900000,
          ),
          _account(
            id: 'a2',
            name: 'Евро',
            currencyCode: 'EUR',
            balance: 0,
            sortOrder: 1,
          ),
          _account(
            id: 'a3',
            name: 'Наличные',
            currencyCode: 'RUB',
            balance: 0,
            sortOrder: 2,
          ),
        ],
        rates: [_rate('RUB', 90), _rate('EUR', 0.9)],
      );

      await _openTransfer(tester);
      await _pickAccount(tester, isSource: true, name: 'Карта');
      await _pickAccount(tester, isSource: false, name: 'Евро');

      await tester.enterText(find.widgetWithText(TextField, 'Списать'), '9000');
      await tester.pumpAndSettle();
      // The bank credited a little less than the stored rate says.
      await tester.enterText(
        find.widgetWithText(TextField, 'Зачислить'),
        '88,50',
      );
      await tester.pumpAndSettle();

      // Change of mind: the money goes to the other rouble account instead.
      await _pickAccount(tester, isSource: false, name: 'Наличные');
      // Same currency on both sides, so there is no «Зачислить» field to correct.
      expect(find.widgetWithText(TextField, 'Зачислить'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Перевести'));
      await tester.pumpAndSettle();

      final stored = {
        for (final account in await repository.getAll())
          account.id: account.balance,
      };
      expect(stored['a1'], 0, reason: '9000 ₽ left the source account');
      expect(
        stored['a3'],
        900000,
        reason: 'a same-currency transfer must credit the debited amount',
      );
    });
  });
}
