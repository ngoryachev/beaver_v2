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

/// «Обновить сейчас» with both rate sources down: the screen has to say so and
/// keep the stored rate, rather than fail silently or wipe the table.
const _userId = 'u1';

/// Both sources unreachable.
class _DeadClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw http.ClientException('Нет соединения', request.url);
  }
}

Future<InMemoryRatesRepository> _pumpSettings(WidgetTester tester) async {
  final rates = InMemoryRatesRepository([
    Rate(
      userId: _userId,
      code: 'RUB',
      ratePerUsd: 90,
      source: RateSource.auto,
      updatedAt: DateTime.utc(2026, 9, 1),
    ),
  ]);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_userId),
        accountsRepositoryProvider.overrideWithValue(
          InMemoryAccountsRepository(const [
            Account(
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
        ratesRepositoryProvider.overrideWithValue(rates),
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(
            const UserSettings(userId: _userId, baseCurrency: 'RUB'),
          ),
        ),
        rateFetcherProvider.overrideWithValue(RateFetcher(_DeadClient())),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return rates;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('«Обновить сейчас» with no network', () {
    testWidgets('reports the failure and keeps the stored rate', (
      tester,
    ) async {
      final rates = await _pumpSettings(tester);

      await tester.tap(find.text('Обновить сейчас'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Не удалось обновить курсы'),
        findsOneWidget,
        reason: 'a silent failure would look like a successful refresh',
      );
      final stored = await rates.getAll();
      expect(stored.single.ratePerUsd, 90);
      expect(stored.single.updatedAt, DateTime.utc(2026, 9, 1));
    });
  });
}
