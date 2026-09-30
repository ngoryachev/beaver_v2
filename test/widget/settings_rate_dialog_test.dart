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

/// Never reaches the network; «Обновить сейчас» is not what these tests exercise.
class _FakeClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'usd': <String, double>{}}))),
        200,
      );
}

Future<InMemoryRatesRepository> _pumpSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final ratesRepository = InMemoryRatesRepository([
    Rate(
      userId: _userId,
      code: 'EUR',
      ratePerUsd: 0.9,
      source: RateSource.auto,
      updatedAt: DateTime.utc(2026, 9, 20),
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
            Account(
              id: 'a2',
              userId: _userId,
              name: 'Евро',
              currencyCode: 'EUR',
              balance: 50000,
            ),
          ]),
        ),
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
        rateFetcherProvider.overrideWithValue(RateFetcher(_FakeClient())),
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
  return ratesRepository;
}

/// Closing the «Курс XXX» dialog must not blow up.
///
/// `_editRate` disposes its `TextEditingController` on the line after
/// `await showDialog(...)`. That future completes as soon as `Navigator.pop`
/// runs, while the dialog is still playing its exit transition and its
/// `TextField` is still being rebuilt — so the next frame touches a disposed
/// controller and throws «A TextEditingController was used after being
/// disposed». In a debug or profile build that surfaces to the user as an error
/// screen; in the tests it poisons every later frame.
void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('closing the manual-rate dialog', () {
    testWidgets('saving a rate does not throw', (tester) async {
      final rates = await _pumpSettings(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Задать').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0,95');
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      // The write itself lands...
      final stored = await rates.getAll();
      expect(stored.single.ratePerUsd, 0.95);
      expect(stored.single.source, RateSource.manual);
      // ...but the dialog's controller must survive the closing animation.
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelling does not throw', (tester) async {
      await _pumpSettings(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Задать').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
