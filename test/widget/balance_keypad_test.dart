import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_scenarios_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/scenario.dart';
import 'package:beaver_v2/domain/models/user_settings.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/screens/home/balance_edit_sheet.dart';
import 'package:beaver_v2/presentation/screens/home/widgets/amount_keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// The keypad is the only way a balance is typed, and its digit handling decides
/// the integer that reaches the database. The existing suite drives it with
/// whole amounts only; these cover the branches that shape the fractional part —
/// the decimal separator, the precision cap and backspace.
const _userId = 'u1';

Account _account({String currencyCode = 'RUB', int balance = 100000}) =>
    Account(
      id: 'a1',
      userId: _userId,
      name: 'Карта',
      currencyCode: currencyCode,
      balance: balance,
    );

/// Pumps the real sheet over in-memory repositories and returns the repository
/// so a test can read back exactly what was stored.
Future<InMemoryAccountsRepository> pumpSheet(
  WidgetTester tester,
  Account account,
) async {
  final repository = InMemoryAccountsRepository([account]);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_userId),
        accountsRepositoryProvider.overrideWithValue(repository),
        plannedOpsRepositoryProvider.overrideWithValue(
          InMemoryPlannedOpsRepository(),
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
      child: MaterialApp(
        home: Scaffold(body: BalanceEditSheet(account: account)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> tapKeys(WidgetTester tester, List<String> keys) async {
  for (final key in keys) {
    await tester.tap(find.widgetWithText(OutlinedButton, key));
    await tester.pump();
  }
}

/// The amount display, told apart from the identically-labelled keypad keys by
/// its alignment — the keys set no `textAlign`.
Finder display(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      widget.data == text &&
      widget.textAlign == TextAlign.right,
);

Future<void> tapBackspace(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.backspace_outlined));
  await tester.pump();
}

Future<int> save(WidgetTester tester, InMemoryAccountsRepository repo) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
  await tester.pumpAndSettle();
  return (await repo.getAll()).single.balance;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('a typed fraction is stored as minor units', (tester) async {
    final repo = await pumpSheet(tester, _account());
    await tapKeys(tester, ['1', '2', ',', '3', '4']);

    expect(await save(tester, repo), 1234);
  });

  testWidgets('a single fractional digit is tenths, not hundredths', (
    tester,
  ) async {
    final repo = await pumpSheet(tester, _account());
    await tapKeys(tester, ['7', ',', '5']);

    // 7,5 ₽ is 750 kopecks. Reading the 5 as hundredths would store 705.
    expect(await save(tester, repo), 750);
  });

  testWidgets('a leading separator is a usable zero', (tester) async {
    final repo = await pumpSheet(tester, _account());
    await tapKeys(tester, [',', '5']);

    expect(display('0,5'), findsOneWidget);
    expect(await save(tester, repo), 50);
  });

  testWidgets('a third fractional digit is refused', (tester) async {
    final repo = await pumpSheet(tester, _account());
    await tapKeys(tester, ['1', ',', '9', '9', '9']);

    // The extra 9 must not be accepted and then rounded away on save: what is
    // displayed has to be what is stored.
    expect(display('1,99'), findsOneWidget);
    expect(await save(tester, repo), 199);
  });

  testWidgets('a second separator is refused', (tester) async {
    final repo = await pumpSheet(tester, _account());
    await tapKeys(tester, ['1', ',', ',', '5']);

    expect(await save(tester, repo), 150);
  });

  testWidgets('a leading zero is replaced, not prepended', (tester) async {
    final repo = await pumpSheet(tester, _account());
    await tapKeys(tester, ['0', '0', '5']);

    expect(display('5'), findsOneWidget);
    expect(await save(tester, repo), 500);
  });

  testWidgets('backspace removes the last key, separator included', (
    tester,
  ) async {
    final repo = await pumpSheet(tester, _account());
    await tapKeys(tester, ['1', '2', ',', '5']);
    await tapBackspace(tester);
    await tapBackspace(tester);

    expect(display('12'), findsOneWidget);
    expect(await save(tester, repo), 1200);
  });

  testWidgets('backspacing everything away disables saving', (tester) async {
    await pumpSheet(tester, _account());
    await tapKeys(tester, ['4']);
    await tapBackspace(tester);
    // One more than there is to erase: it must not throw on an empty string.
    await tapBackspace(tester);

    expect(find.text('Введите сумму'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Сохранить'),
      ).onPressed,
      isNull,
    );
  });

  testWidgets('a zero-decimal currency offers no separator', (tester) async {
    final repo = await pumpSheet(
      tester,
      _account(currencyCode: 'JPY', balance: 5000),
    );

    expect(find.widgetWithText(OutlinedButton, ','), findsNothing);
    await tapKeys(tester, ['1', '2', '0']);

    // 120 ¥ is 120 minor units: no scaling for a currency without a fraction.
    expect(await save(tester, repo), 120);
  });

  testWidgets('«−» subtracts the typed fraction from the current balance', (
    tester,
  ) async {
    final repo = await pumpSheet(tester, _account(balance: 100000));
    // The segment itself, not the SegmentedButton around it: tapping the
    // parent lands in the middle of the row, which is «+».
    expect(find.byType(SegmentedButton<KeypadMode>), findsOneWidget);
    await tester.tap(find.text('−'));
    await tester.pump();
    await tapKeys(tester, ['2', '5', ',', '5']);

    expect(await save(tester, repo), 100000 - 2550);
  });
}
