import 'dart:convert';

import 'package:beaver_v2/app.dart';
import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_scenarios_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/data/rates/rate_fetcher.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/models/scenario.dart';
import 'package:beaver_v2/domain/models/user_settings.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/screens/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';

const _userId = 'u1';

/// Serves the primary rate source, so «Обновить сейчас» never reaches the network.
class _FakeClient extends http.BaseClient {
  final Map<String, double> rates;
  int calls = 0;

  _FakeClient(this.rates);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    final body = jsonEncode({
      'usd': {for (final e in rates.entries) e.key.toLowerCase(): e.value},
    });
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
}

Account _account({
  required String id,
  required String name,
  required String code,
  int balance = 100000,
  bool archived = false,
}) => Account(
  id: id,
  userId: _userId,
  name: name,
  currencyCode: code,
  balance: balance,
  archived: archived,
);

class _Harness {
  final InMemoryAccountsRepository accounts;
  final InMemoryRatesRepository rates;
  final _FakeClient client;

  _Harness(this.accounts, this.rates, this.client);
}

Future<_Harness> _pumpSettings(
  WidgetTester tester, {
  required List<Account> accounts,
  List<Rate> rates = const [],
  Map<String, double> fetched = const {'EUR': 0.9, 'RUB': 90.0},
}) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final accountsRepository = InMemoryAccountsRepository(accounts);
  final ratesRepository = InMemoryRatesRepository(rates);
  final client = _FakeClient(fetched);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_userId),
        accountsRepositoryProvider.overrideWithValue(accountsRepository),
        plannedOpsRepositoryProvider.overrideWithValue(
          InMemoryPlannedOpsRepository(),
        ),
        scenariosRepositoryProvider.overrideWithValue(
          InMemoryScenariosRepository([
            Scenario(id: 's1', userId: _userId, name: 'Все', isDefault: true),
          ]),
        ),
        ratesRepositoryProvider.overrideWithValue(ratesRepository),
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(
            const UserSettings(userId: _userId, baseCurrency: 'RUB'),
          ),
        ),
        rateFetcherProvider.overrideWithValue(RateFetcher(client)),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: BeaverApp.supportedLocales,
        localizationsDelegates: BeaverApp.localizationsDelegates,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(accountsRepository, ratesRepository, client);
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('the rate table', () {
    testWidgets('lists the currencies in use and marks USD as the pivot', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        accounts: [
          _account(id: 'a1', name: 'Карта', code: 'RUB'),
          _account(id: 'a2', name: 'Наличные', code: 'USD'),
          _account(id: 'a3', name: 'Евро', code: 'EUR'),
        ],
        rates: [
          Rate(
            userId: _userId,
            code: 'RUB',
            ratePerUsd: 90,
            source: RateSource.auto,
            updatedAt: DateTime.utc(2026, 9, 20),
          ),
        ],
      );

      expect(find.text('USD'), findsOneWidget);
      expect(find.textContaining('опорная валюта'), findsOneWidget);
      // RUB has an auto rate, EUR has none at all.
      expect(find.textContaining('90 за 1 USD · авто'), findsOneWidget);
      expect(find.text('Нет курса'), findsOneWidget);
      // A currency nobody holds is not worth a row.
      expect(find.text('JPY'), findsNothing);
    });

    testWidgets('a manual rate is labelled as such and can be reset', (
      tester,
    ) async {
      // Seeded rather than typed: closing the «Задать» dialog is covered by
      // settings_rate_dialog_test.dart.
      await _pumpSettings(
        tester,
        accounts: [
          _account(id: 'a1', name: 'Карта', code: 'RUB'),
          _account(id: 'a2', name: 'Евро', code: 'EUR'),
        ],
        rates: [
          Rate(
            userId: _userId,
            code: 'EUR',
            ratePerUsd: 0.95,
            source: RateSource.manual,
            updatedAt: DateTime.utc(2026, 9, 20),
          ),
        ],
      );

      expect(find.textContaining('вручную'), findsOneWidget);
      // Only a manual row can be reset; an auto row has nothing to undo.
      expect(find.text('Сбросить'), findsOneWidget);
    });

    testWidgets('a rate that is not a positive number is refused', (
      tester,
    ) async {
      final harness = await _pumpSettings(
        tester,
        accounts: [
          _account(id: 'a1', name: 'Карта', code: 'RUB'),
          _account(id: 'a2', name: 'Евро', code: 'EUR'),
        ],
      );

      await tester.tap(find.widgetWithText(TextButton, 'Задать').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0');
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      // The dialog stays open with an error instead of storing a rate that would
      // make every conversion through it meaningless.
      expect(find.text('Введите число больше нуля'), findsOneWidget);
      expect(await harness.rates.getAll(), isEmpty);
    });

    testWidgets('«Сбросить» deletes the row so a refresh can refill it', (
      tester,
    ) async {
      final harness = await _pumpSettings(
        tester,
        accounts: [
          _account(id: 'a1', name: 'Карта', code: 'RUB'),
          _account(id: 'a2', name: 'Евро', code: 'EUR'),
        ],
        rates: [
          Rate(
            userId: _userId,
            code: 'RUB',
            ratePerUsd: 90,
            source: RateSource.auto,
            updatedAt: DateTime.utc(2026, 9, 20),
          ),
          Rate(
            userId: _userId,
            code: 'EUR',
            ratePerUsd: 0.5,
            source: RateSource.manual,
            updatedAt: DateTime.utc(2026, 9, 20),
          ),
        ],
      );

      expect(find.text('Нет курса'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Сбросить'));
      await tester.pumpAndSettle();

      // Deleted, not overwritten with an auto value: the row has to be absent
      // for the next refresh to fill it in.
      expect((await harness.rates.getAll()).map((rate) => rate.code), ['RUB']);
      expect(find.text('Нет курса'), findsOneWidget);
      expect(find.text('Сбросить'), findsNothing);
    });

    testWidgets('«Обновить сейчас» refills an auto rate but not a manual one', (
      tester,
    ) async {
      final harness = await _pumpSettings(
        tester,
        accounts: [
          _account(id: 'a1', name: 'Карта', code: 'RUB'),
          _account(id: 'a2', name: 'Евро', code: 'EUR'),
        ],
        rates: [
          Rate(
            userId: _userId,
            code: 'EUR',
            ratePerUsd: 0.5,
            source: RateSource.manual,
            updatedAt: DateTime.utc(2026, 9, 20),
          ),
        ],
        fetched: const {'RUB': 80.0, 'EUR': 0.9},
      );

      await tester.tap(find.text('Обновить сейчас'));
      await tester.pumpAndSettle();

      final stored = {
        for (final rate in await harness.rates.getAll()) rate.code: rate,
      };
      expect(harness.client.calls, 1);
      expect(stored['RUB']!.ratePerUsd, 80.0);
      expect(stored['RUB']!.source, RateSource.auto);
      // The user's own number survives the refresh.
      expect(stored['EUR']!.ratePerUsd, 0.5);
      expect(stored['EUR']!.source, RateSource.manual);
    });
  });

  group('accounts', () {
    testWidgets('an active account can be archived and brought back', (
      tester,
    ) async {
      final harness = await _pumpSettings(
        tester,
        accounts: [_account(id: 'a1', name: 'Копилка', code: 'RUB')],
      );

      expect(find.text('Архивных счетов нет'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'В архив'));
      await tester.pumpAndSettle();

      expect((await harness.accounts.getAll()).single.archived, isTrue);
      expect(find.text('Архивных счетов нет'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Вернуть'));
      await tester.pumpAndSettle();

      expect((await harness.accounts.getAll()).single.archived, isFalse);
      expect(find.text('Архивных счетов нет'), findsOneWidget);
    });

    testWidgets('archiving never changes the balance', (tester) async {
      final harness = await _pumpSettings(
        tester,
        accounts: [
          _account(id: 'a1', name: 'Копилка', code: 'RUB', balance: 123456),
        ],
      );

      await tester.tap(find.widgetWithText(TextButton, 'В архив'));
      await tester.pumpAndSettle();

      expect((await harness.accounts.getAll()).single.balance, 123456);
    });

    testWidgets('the base currency follows the accounts that exist', (
      tester,
    ) async {
      // Stored base is RUB, but the only account is in euro, so the invariant
      // «base currency is a currency of some live account» must move it.
      await _pumpSettings(
        tester,
        accounts: [_account(id: 'a1', name: 'Евро', code: 'EUR')],
      );

      expect(find.textContaining('EUR · итог считается в ней'), findsOneWidget);
    });
  });

  group('a manual rate whose currency is no longer used', () {
    testWidgets('stays listed so «Сбросить» can still reach it', (
      tester,
    ) async {
      // The row survives in `rates` and the auto refresh keeps skipping it, so
      // dropping it from the list would strand a stale override that resurfaces
      // the moment a EUR account is added again.
      await _pumpSettings(
        tester,
        accounts: [_account(id: 'a1', name: 'Карта', code: 'RUB')],
        rates: [
          Rate(
            userId: _userId,
            code: 'EUR',
            ratePerUsd: 0.8,
            source: RateSource.manual,
            updatedAt: DateTime.utc(2026, 9, 20),
          ),
        ],
      );

      expect(find.text('EUR'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Сбросить'), findsOneWidget);
    });

    testWidgets('an orphaned auto rate is not listed', (tester) async {
      // Only a manual override needs the escape hatch; an unused auto row is
      // noise and will be refreshed away on its own.
      await _pumpSettings(
        tester,
        accounts: [_account(id: 'a1', name: 'Карта', code: 'RUB')],
        rates: [
          Rate(
            userId: _userId,
            code: 'EUR',
            ratePerUsd: 0.8,
            source: RateSource.auto,
            updatedAt: DateTime.utc(2026, 9, 20),
          ),
        ],
      );

      expect(find.text('EUR'), findsNothing);
    });
  });
}
