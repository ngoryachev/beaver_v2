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
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/screens/home/home_screen.dart';
import 'package:beaver_v2/presentation/screens/home/widgets/account_card.dart';
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
  bool archived = false,
}) => Account(
  id: id,
  userId: _userId,
  name: name,
  currencyCode: currencyCode,
  balance: balance,
  sortOrder: sortOrder,
  archived: archived,
);

Rate _rate(String code, double perUsd) => Rate(
  userId: _userId,
  code: code,
  ratePerUsd: perUsd,
  source: RateSource.auto,
  updatedAt: DateTime.now().toUtc(),
);

/// Builds the home screen over in-memory repositories. Supabase is never touched:
/// the repository providers are replaced wholesale.
Future<InMemoryAccountsRepository> pumpHome(
  WidgetTester tester, {
  required List<Account> accounts,
  List<PlannedOp> ops = const [],
  List<Rate> rates = const [],
  String baseCurrency = 'RUB',
}) async {
  final accountsRepository = InMemoryAccountsRepository(accounts);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_userId),
        accountsRepositoryProvider.overrideWithValue(accountsRepository),
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
  // Two pumps: the first shows the spinner, the second the loaded data.
  await tester.pumpAndSettle();
  return accountsRepository;
}

/// The headline total, read straight off its keyed widget.
String totalText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('home-total'))).data!;

/// Digits only, so an expectation does not depend on grouping or the symbol.
String digitsOf(String text) => text.replaceAll(RegExp(r'[^\d,-]'), '');

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('HomeScreen — totals and account cards', () {
    testWidgets('shows every live account and their sum', (tester) async {
      await pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 100000,
          ),
          _account(
            id: 'a2',
            name: 'Наличные',
            currencyCode: 'RUB',
            balance: 50000,
            sortOrder: 1,
          ),
        ],
      );

      expect(find.text('Карта'), findsOneWidget);
      expect(find.text('Наличные'), findsOneWidget);
      // 1000.00 + 500.00 = 1500.00 ₽
      expect(digitsOf(totalText(tester)), '1500,00');
    });

    testWidgets('leaves archived accounts out of the list and the total', (
      tester,
    ) async {
      await pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 100000,
          ),
          _account(
            id: 'a2',
            name: 'Старый',
            currencyCode: 'RUB',
            balance: 900000,
            archived: true,
          ),
        ],
      );

      expect(find.text('Старый'), findsNothing);
      expect(digitsOf(totalText(tester)), '1000,00');
    });

    testWidgets('converts a foreign account into the base currency', (
      tester,
    ) async {
      await pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 90000,
          ),
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

      // 100 EUR ÷ 0.9 × 90 = 10 000 RUB, plus 900 RUB.
      expect(digitsOf(totalText(tester)), '10900,00');
    });

    testWidgets('warns about a currency with no rate', (tester) async {
      await pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 100000,
          ),
          _account(
            id: 'a2',
            name: 'Тенге',
            currencyCode: 'KZT',
            balance: 500000,
            sortOrder: 1,
          ),
        ],
        rates: [_rate('RUB', 90)],
      );

      expect(find.textContaining('Без курса'), findsOneWidget);
      expect(find.textContaining('KZT'), findsWidgets);
      // The KZT balance is left out rather than counted as zero.
      expect(digitsOf(totalText(tester)), '1000,00');
    });
  });

  group('HomeScreen — editing a balance', () {
    testWidgets('«=» replaces the balance and updates the card and the total', (
      tester,
    ) async {
      final repository = await pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 100000,
          ),
        ],
      );

      await tester.tap(find.text('Карта'));
      await tester.pumpAndSettle();

      // Type 250 in «=» mode, the default.
      for (final digit in ['2', '5', '0']) {
        await tester.tap(find.widgetWithText(OutlinedButton, digit));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      final stored = await repository.getAll();
      expect(stored.single.balance, 25000);
      expect(digitsOf(totalText(tester)), '250,00');
      // Scoped to the card: with one account the total and the 30-day forecast
      // read the same number.
      expect(
        find.descendant(
          of: find.byType(AccountCard),
          matching: find.text('250,00 ₽'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('«−» subtracts from the current balance', (tester) async {
      final repository = await pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 100000,
          ),
        ],
      );

      await tester.tap(find.text('Карта'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('−'));
      await tester.pump();
      for (final digit in ['2', '5', '0']) {
        await tester.tap(find.widgetWithText(OutlinedButton, digit));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      // 1000.00 − 250.00 = 750.00
      expect((await repository.getAll()).single.balance, 75000);
      expect(digitsOf(totalText(tester)), '750,00');
    });

    testWidgets('«+» adds to the current balance', (tester) async {
      final repository = await pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 100000,
          ),
        ],
      );

      await tester.tap(find.text('Карта'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('+'));
      await tester.pump();
      for (final digit in ['5', '0']) {
        await tester.tap(find.widgetWithText(OutlinedButton, digit));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      expect((await repository.getAll()).single.balance, 105000);
      expect(digitsOf(totalText(tester)), '1050,00');
    });
  });

  group('HomeScreen — transfers', () {
    testWidgets('a same-currency transfer moves money between the cards', (
      tester,
    ) async {
      final repository = await pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 100000,
          ),
          _account(
            id: 'a2',
            name: 'Наличные',
            currencyCode: 'RUB',
            balance: 50000,
            sortOrder: 1,
          ),
        ],
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Перевод'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Карта').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Наличные').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Списать'), '300');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Перевести'));
      await tester.pumpAndSettle();

      final stored = {
        for (final a in await repository.getAll()) a.id: a.balance,
      };
      expect(stored['a1'], 70000);
      expect(stored['a2'], 80000);
      // A transfer moves money, it does not create or destroy it.
      expect(digitsOf(totalText(tester)), '1500,00');
      expect(find.text('700,00 ₽'), findsOneWidget);
      expect(find.text('800,00 ₽'), findsOneWidget);
    });

    testWidgets(
      'a cross-currency transfer prefills the credited side by rate',
      (tester) async {
        final repository = await pumpHome(
          tester,
          accounts: [
            _account(
              id: 'a1',
              name: 'Рубли',
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
          ],
          rates: [_rate('RUB', 90), _rate('EUR', 0.9)],
        );

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Перевод'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Рубли').last);
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButtonFormField<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Евро').last);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Списать'),
          '9000',
        );
        await tester.pumpAndSettle();

        // 9000 RUB ÷ 90 × 0.9 = 90 EUR, prefilled and editable.
        final credited = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Зачислить'),
        );
        expect(credited.controller!.text, '90');

        await tester.tap(find.widgetWithText(FilledButton, 'Перевести'));
        await tester.pumpAndSettle();

        final stored = {
          for (final a in await repository.getAll()) a.id: a.balance,
        };
        expect(stored['a1'], 0);
        expect(stored['a2'], 9000);
      },
    );

    testWidgets('an edited credited amount overrides the rate', (tester) async {
      final repository = await pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Рубли',
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
        ],
        rates: [_rate('RUB', 90), _rate('EUR', 0.9)],
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Перевод'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Рубли').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Евро').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Списать'), '9000');
      await tester.pumpAndSettle();
      // The bank actually credited 88,50 — the stored rate must not win.
      await tester.enterText(
        find.widgetWithText(TextField, 'Зачислить'),
        '88,50',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Перевести'));
      await tester.pumpAndSettle();

      final stored = {
        for (final a in await repository.getAll()) a.id: a.balance,
      };
      expect(stored['a2'], 8850);
    });
  });

  group('HomeScreen — cycling the total currency', () {
    testWidgets('tapping the total cycles through the account currencies', (
      tester,
    ) async {
      await pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Рубли',
            currencyCode: 'RUB',
            balance: 90000,
          ),
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

      // Starts in RUB: 900 RUB + 100 EUR (= 10 000 RUB).
      expect(totalText(tester), contains('₽'));
      expect(digitsOf(totalText(tester)), '10900,00');

      await tester.tap(find.byKey(const Key('home-total')));
      await tester.pumpAndSettle();

      // Now EUR: 9 EUR + 100 EUR.
      expect(totalText(tester), contains('€'));
      expect(digitsOf(totalText(tester)), '109,00');

      // And back round to the start.
      await tester.tap(find.byKey(const Key('home-total')));
      await tester.pumpAndSettle();
      expect(totalText(tester), contains('₽'));
      expect(digitsOf(totalText(tester)), '10900,00');
    });

    testWidgets('with a single currency the total is not tappable', (
      tester,
    ) async {
      await pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 100000,
          ),
        ],
      );

      await tester.tap(find.byKey(const Key('home-total')));
      await tester.pumpAndSettle();

      expect(totalText(tester), contains('₽'));
      expect(digitsOf(totalText(tester)), '1000,00');
    });

    testWidgets('an archived account currency drops out of the cycle', (
      tester,
    ) async {
      await pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Рубли',
            currencyCode: 'RUB',
            balance: 90000,
          ),
          _account(
            id: 'a2',
            name: 'Старые евро',
            currencyCode: 'EUR',
            balance: 10000,
            archived: true,
            sortOrder: 1,
          ),
        ],
        rates: [_rate('RUB', 90), _rate('EUR', 0.9)],
      );

      await tester.tap(find.byKey(const Key('home-total')));
      await tester.pumpAndSettle();

      // EUR is archived, so RUB is the only option left.
      expect(totalText(tester), contains('₽'));
      expect(digitsOf(totalText(tester)), '900,00');
    });
  });

  group('HomeScreen — the 30-day forecast widget', () {
    testWidgets('applies planned operations without touching the balances', (
      tester,
    ) async {
      final today = DateTime.now();
      final repository = await pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 1000000,
          ),
        ],
        ops: [
          PlannedOp(
            id: 'op1',
            userId: _userId,
            title: 'Обед',
            amount: 10000,
            currencyCode: 'RUB',
            kind: OpKind.expense,
            schedule: Schedule.daily,
            startDate: DateTime(today.year, today.month, today.day),
          ),
        ],
      );

      // 31 daily points from today: 10 000,00 − 31 × 100,00 = 6 900,00.
      final forecast = tester
          .widget<Text>(find.byKey(const Key('home-forecast-30')))
          .data!;
      expect(digitsOf(forecast), '6900,00');
      // The stored balance is untouched: operations only ever forecast.
      expect((await repository.getAll()).single.balance, 1000000);
      expect(digitsOf(totalText(tester)), '10000,00');
    });

    testWidgets('a disabled operation leaves the forecast alone', (
      tester,
    ) async {
      final today = DateTime.now();
      await pumpHome(
        tester,
        accounts: [
          _account(
            id: 'a1',
            name: 'Карта',
            currencyCode: 'RUB',
            balance: 1000000,
          ),
        ],
        ops: [
          PlannedOp(
            id: 'op1',
            userId: _userId,
            title: 'Обед',
            amount: 10000,
            currencyCode: 'RUB',
            kind: OpKind.expense,
            schedule: Schedule.daily,
            startDate: DateTime(today.year, today.month, today.day),
            enabled: false,
          ),
        ],
      );

      final forecast = tester
          .widget<Text>(find.byKey(const Key('home-forecast-30')))
          .data!;
      expect(digitsOf(forecast), '10000,00');
    });
  });

  group('HomeScreen — empty state', () {
    testWidgets('prompts for a first account', (tester) async {
      await pumpHome(tester, accounts: const []);

      expect(find.textContaining('Пока нет счетов'), findsOneWidget);
    });
  });
}
