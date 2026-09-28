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
import 'package:beaver_v2/presentation/screens/home/home_screen.dart';
import 'package:beaver_v2/presentation/screens/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';

const _userId = 'u1';

/// The manual-rate dialog parses with `double.tryParse`, which — unlike
/// `Money.tryParse`, whose regex rejects it — returns `double.infinity` for the
/// literal text `Infinity`. The only guard afterwards is `parsed <= 0`, and
/// infinity passes it, so the value is stored as a real rate.
///
/// Every conversion then routes through `Money.fromMajor`, whose `.round()`
/// throws `UnsupportedError` on a non-finite double. The rate row outlives the
/// session (Postgres `DOUBLE PRECISION` accepts `Infinity` under
/// `CHECK (rate_per_usd > 0)`), so the crash comes back on every launch and the
/// «Сбросить» button on the settings screen is the only way out.
class _FakeClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'usd': <String, double>{}}))),
        200,
      );
}

const _accounts = [
  Account(
    id: 'a1',
    userId: _userId,
    name: 'Карта',
    currencyCode: 'RUB',
    balance: 100000,
  ),
  Account(
    id: 'a2',
    userId: _userId,
    name: 'Евро',
    currencyCode: 'EUR',
    balance: 50000,
  ),
];

List<Override> _overrides(
  InMemoryRatesRepository rates, {
  String baseCurrency = 'RUB',
}) => [
  currentUserIdProvider.overrideWithValue(_userId),
  accountsRepositoryProvider.overrideWithValue(
    InMemoryAccountsRepository(_accounts),
  ),
  plannedOpsRepositoryProvider.overrideWithValue(InMemoryPlannedOpsRepository()),
  scenariosRepositoryProvider.overrideWithValue(
    InMemoryScenariosRepository([
      Scenario(id: 's1', userId: _userId, name: 'Все', isDefault: true),
    ]),
  ),
  ratesRepositoryProvider.overrideWithValue(rates),
  settingsRepositoryProvider.overrideWithValue(
    InMemorySettingsRepository(
      UserSettings(userId: _userId, baseCurrency: baseCurrency),
    ),
  ),
  rateFetcherProvider.overrideWithValue(RateFetcher(_FakeClient())),
];

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('the manual-rate dialog refuses a non-finite rate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final rates = InMemoryRatesRepository([]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(rates),
        child: MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: BeaverApp.supportedLocales,
          localizationsDelegates: BeaverApp.localizationsDelegates,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Задать').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Infinity');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    final stored = await rates.getAll();
    expect(
      stored.where((rate) => !rate.ratePerUsd.isFinite),
      isEmpty,
      reason: 'a non-finite rate must be rejected, not stored',
    );
  });

  // The base currency is the one carrying the non-finite rate, so it is the
  // *target* of every conversion — `major / fromRate * toRate` is then infinite
  // and `Money.fromMajor` throws. With the non-finite rate on the source side
  // the division silently yields 0 instead, which is wrong but not fatal.
  testWidgets('a stored non-finite rate does not crash the home screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          InMemoryRatesRepository([
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
              ratePerUsd: double.infinity,
              source: RateSource.manual,
              updatedAt: DateTime.utc(2026, 9, 20),
            ),
          ]),
          baseCurrency: 'EUR',
        ),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
