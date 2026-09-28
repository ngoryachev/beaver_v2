import 'package:beaver_v2/app.dart';
import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_scenarios_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/domain/models/account.dart';
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

/// Creating an account is the first thing a new user does and the only way a
/// currency ever enters the app, so what this dialog stores decides the total,
/// the base-currency cycle and which rates get fetched.
const _userId = 'u1';

Future<InMemoryAccountsRepository> _pumpHome(
  WidgetTester tester, {
  List<Account> accounts = const [],
  List<Rate> rates = const [],
}) async {
  // Tall enough for the dialog's form to lay out in full.
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repository = InMemoryAccountsRepository(accounts);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_userId),
        accountsRepositoryProvider.overrideWithValue(repository),
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
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: BeaverApp.supportedLocales,
        localizationsDelegates: BeaverApp.localizationsDelegates,
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Счёт'));
  await tester.pumpAndSettle();
}

Future<void> _pickCurrency(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('a new account is stored with its name, currency and balance', (
    tester,
  ) async {
    final repository = await _pumpHome(tester);
    await _openDialog(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название'),
      'Карта',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Баланс'),
      '1 234,56',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
    await tester.pumpAndSettle();

    final stored = (await repository.getAll()).single;
    expect(stored.name, 'Карта');
    expect(stored.currencyCode, 'RUB');
    expect(stored.balance, 123456);
    expect(stored.archived, isFalse);
    // And it is on screen, counted into the total.
    expect(find.text(formatMoney(123456, 'RUB')), findsWidgets);
  });

  testWidgets('a blank balance starts the account at zero', (tester) async {
    final repository = await _pumpHome(tester);
    await _openDialog(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название'),
      'Наличные',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
    await tester.pumpAndSettle();

    expect((await repository.getAll()).single.balance, 0);
  });

  testWidgets('an empty name blocks the save', (tester) async {
    final repository = await _pumpHome(tester);
    await _openDialog(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
    await tester.pumpAndSettle();

    expect(find.text('Введите название'), findsOneWidget);
    expect(await repository.getAll(), isEmpty);
  });

  testWidgets('an unparseable balance is refused instead of becoming zero', (
    tester,
  ) async {
    final repository = await _pumpHome(tester);
    await _openDialog(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название'),
      'Карта',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Баланс'),
      'сто рублей',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
    await tester.pumpAndSettle();

    expect(find.text('Введите сумму'), findsOneWidget);
    expect(await repository.getAll(), isEmpty);
  });

  testWidgets('a zero-decimal currency stores whole units', (tester) async {
    final repository = await _pumpHome(tester);
    await _openDialog(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название'),
      'Иены',
    );
    await _pickCurrency(tester, 'JPY ¥');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Баланс'),
      '5000',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
    await tester.pumpAndSettle();

    final stored = (await repository.getAll()).single;
    expect(stored.currencyCode, 'JPY');
    // JPY has no minor unit: 5000 yen is 5000, not 500 000.
    expect(stored.balance, 5000);
  });

  testWidgets('a second account is appended after the first, not on top of it', (
    tester,
  ) async {
    final repository = await _pumpHome(
      tester,
      accounts: const [
        Account(
          id: 'a1',
          userId: _userId,
          name: 'Карта',
          currencyCode: 'RUB',
          balance: 100000,
          sortOrder: 7,
        ),
      ],
    );
    await _openDialog(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название'),
      'Наличные',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Баланс'), '500');
    await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
    await tester.pumpAndSettle();

    final all = await repository.getAll();
    expect(all.map((a) => a.name), ['Карта', 'Наличные']);
    expect(all.last.sortOrder, greaterThan(all.first.sortOrder));
    // Both are counted: 1000 ₽ + 500 ₽.
    expect(find.text(formatMoney(150000, 'RUB')), findsWidgets);
  });
}
