import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_scenarios_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/models/scenario.dart';
import 'package:beaver_v2/domain/models/user_settings.dart';
import 'package:beaver_v2/presentation/providers/projection_provider.dart';
import 'package:beaver_v2/presentation/providers/rates_provider.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _userId = 'u1';

/// `projectionProvider` is a plain (non-auto-dispose) `Provider.family`, so every
/// distinct argument it is ever read with stays in the container for the life of
/// the app. That is fine for a day-granular date; it is not fine for a key that
/// changes on every rebuild.
void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('the home screen does not cache a new projection per rebuild', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue(_userId),
          accountsRepositoryProvider.overrideWithValue(
            InMemoryAccountsRepository([
              const Account(
                id: 'a1',
                userId: _userId,
                name: 'Карта',
                currencyCode: 'RUB',
                balance: 100000,
              ),
            ]),
          ),
          plannedOpsRepositoryProvider.overrideWithValue(
            InMemoryPlannedOpsRepository(const []),
          ),
          scenariosRepositoryProvider.overrideWithValue(
            InMemoryScenariosRepository([
              Scenario(id: 's1', userId: _userId, name: 'Все', isDefault: true),
            ]),
          ),
          ratesRepositoryProvider.overrideWithValue(
            InMemoryRatesRepository([
              Rate(
                userId: _userId,
                code: 'RUB',
                ratePerUsd: 90,
                source: RateSource.auto,
                updatedAt: DateTime.now().toUtc(),
              ),
            ]),
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

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    int cachedProjections() => container
        .getAllProviderElements()
        .where((element) => element.origin.from == projectionProvider)
        .length;

    final before = cachedProjections();
    expect(before, greaterThan(0));

    // Three data-driven rebuilds of the home screen — nothing about the forecast
    // horizon changed, so nothing new should have to be cached.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      container.invalidate(ratesProvider);
      await tester.pumpAndSettle();
    }

    expect(
      cachedProjections(),
      before,
      reason:
          'each rebuild keyed the family with a fresh DateTime.now(), so the '
          'container keeps one more projection for ever',
    );
  });
}
