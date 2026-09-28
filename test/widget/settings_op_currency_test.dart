import 'dart:convert';

import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_scenarios_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/data/rates/rate_fetcher.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/models/scenario.dart';
import 'package:beaver_v2/domain/models/user_settings.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/screens/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';

/// A currency can enter the app through a planned operation alone — a rent in
/// euro paid from a rouble card. Its rate matters to the forecast just as much,
/// so settings has to list it and the refresh has to ask for it.
const _userId = 'u1';

final _rentInEur = PlannedOp(
  id: 'op1',
  userId: _userId,
  title: 'Аренда',
  amount: 50000,
  currencyCode: 'EUR',
  kind: OpKind.expense,
  schedule: Schedule.monthly,
  startDate: DateTime(2026, 1, 10),
);

/// Serves the primary source with whatever rates it was given.
class _FakeClient extends http.BaseClient {
  final Map<String, double> rates;
  final List<Uri> requests = [];

  _FakeClient(this.rates);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    final body = jsonEncode({
      'usd': {for (final e in rates.entries) e.key.toLowerCase(): e.value},
    });
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
}

Future<InMemoryRatesRepository> _pumpSettings(
  WidgetTester tester,
  _FakeClient client,
) async {
  final rates = InMemoryRatesRepository(const []);

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
          InMemoryPlannedOpsRepository([_rentInEur]),
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
        rateFetcherProvider.overrideWithValue(RateFetcher(client)),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return rates;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('a currency used only by an operation', () {
    testWidgets('is listed in the rate table as having no rate', (
      tester,
    ) async {
      await _pumpSettings(tester, _FakeClient(const {}));

      expect(find.text('EUR'), findsOneWidget);
      final eurRow = find.ancestor(
        of: find.text('EUR'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: eurRow, matching: find.text('Нет курса')),
        findsOneWidget,
      );
    });

    testWidgets('is fetched by «Обновить сейчас»', (tester) async {
      final client = _FakeClient(const {'RUB': 90.0, 'EUR': 0.92});
      final rates = await _pumpSettings(tester, client);

      await tester.tap(find.text('Обновить сейчас'));
      await tester.pumpAndSettle();

      final stored = {
        for (final rate in await rates.getAll()) rate.code: rate.ratePerUsd,
      };
      expect(stored['EUR'], 0.92);
      expect(stored['RUB'], 90.0);
    });
  });
}
