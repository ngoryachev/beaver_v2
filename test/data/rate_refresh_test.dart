import 'dart:async';
import 'dart:convert';

import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/data/rates/rate_fetcher.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/presentation/providers/rate_refresh_provider.dart';
import 'package:beaver_v2/presentation/providers/rates_provider.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _userId = 'u1';

/// Serves the primary rate source, after an optional delay so a test can model
/// the accounts list resolving later than the fetch would like.
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

/// An accounts repository that only answers after [gate] completes — this is what
/// a cold start looks like, with the network round trip still in flight.
class _SlowAccountsRepository extends InMemoryAccountsRepository {
  final Future<void> gate;

  _SlowAccountsRepository(this.gate, List<Account> seed) : super(seed);

  @override
  Future<List<Account>> getAll() async {
    await gate;
    return super.getAll();
  }
}

Account _account(String code) => Account(
  id: 'a-$code',
  userId: _userId,
  name: code,
  currencyCode: code,
  balance: 100000,
);

ProviderContainer _container({
  required InMemoryAccountsRepository accounts,
  required _FakeClient client,
  List<Rate> rates = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue(_userId),
      accountsRepositoryProvider.overrideWithValue(accounts),
      plannedOpsRepositoryProvider.overrideWithValue(
        InMemoryPlannedOpsRepository(),
      ),
      ratesRepositoryProvider.overrideWithValue(InMemoryRatesRepository(rates)),
      settingsRepositoryProvider.overrideWithValue(
        InMemorySettingsRepository(),
      ),
      rateFetcherProvider.overrideWithValue(RateFetcher(client)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('RateRefreshController', () {
    test('waits for the accounts to load before choosing currencies', () async {
      // Regression: the start-up refresh used to read the currency set while the
      // accounts were still loading, find it empty, and silently do nothing.
      final gate = Completer<void>();
      final client = _FakeClient({'RUB': 84.0, 'EUR': 0.88});
      final container = _container(
        accounts: _SlowAccountsRepository(gate.future, [
          _account('RUB'),
          _account('EUR'),
        ]),
        client: client,
      );

      final refresh = container
          .read(rateRefreshProvider.notifier)
          .refreshIfStale();
      // The accounts only arrive after the refresh has already been asked to run.
      gate.complete();
      await refresh;

      final stored =
          container.read(ratesProvider).valueOrNull ?? const <Rate>[];
      expect(
        {for (final rate in stored) rate.code: rate.ratePerUsd},
        {'RUB': 84.0, 'EUR': 0.88},
      );
      expect(stored.every((rate) => rate.source == RateSource.auto), isTrue);
    });

    test('fetches only the currencies actually in use', () async {
      final client = _FakeClient({'RUB': 84.0, 'EUR': 0.88, 'KZT': 500.0});
      final container = _container(
        accounts: InMemoryAccountsRepository([_account('RUB')]),
        client: client,
      );

      await container.read(rateRefreshProvider.notifier).refreshIfStale();

      final stored =
          container.read(ratesProvider).valueOrNull ?? const <Rate>[];
      expect(stored.map((rate) => rate.code), ['RUB']);
    });

    test('leaves a manual rate untouched', () async {
      final client = _FakeClient({'RUB': 84.0});
      final container = _container(
        accounts: InMemoryAccountsRepository([_account('RUB')]),
        client: client,
        rates: [
          Rate(
            userId: _userId,
            code: 'RUB',
            ratePerUsd: 100,
            source: RateSource.manual,
            updatedAt: DateTime.utc(2020, 1, 1),
          ),
        ],
      );

      await container.read(rateRefreshProvider.notifier).refreshIfStale();

      final stored =
          container.read(ratesProvider).valueOrNull ?? const <Rate>[];
      expect(stored.single.ratePerUsd, 100);
      expect(stored.single.source, RateSource.manual);
    });

    test('skips the fetch when a fresh auto rate already exists', () async {
      final client = _FakeClient({'RUB': 84.0});
      final container = _container(
        accounts: InMemoryAccountsRepository([_account('RUB')]),
        client: client,
        rates: [
          Rate(
            userId: _userId,
            code: 'RUB',
            ratePerUsd: 90,
            source: RateSource.auto,
            updatedAt: DateTime.now().toUtc(),
          ),
        ],
      );

      await container.read(rateRefreshProvider.notifier).refreshIfStale();

      expect(client.calls, 0);
      final stored =
          container.read(ratesProvider).valueOrNull ?? const <Rate>[];
      expect(stored.single.ratePerUsd, 90);
    });

    test(
      'refetches when the newest auto rate is older than 24 hours',
      () async {
        final client = _FakeClient({'RUB': 84.0});
        final container = _container(
          accounts: InMemoryAccountsRepository([_account('RUB')]),
          client: client,
          rates: [
            Rate(
              userId: _userId,
              code: 'RUB',
              ratePerUsd: 90,
              source: RateSource.auto,
              updatedAt: DateTime.now().toUtc().subtract(
                const Duration(hours: 25),
              ),
            ),
          ],
        );

        await container.read(rateRefreshProvider.notifier).refreshIfStale();

        expect(client.calls, 1);
        final stored =
            container.read(ratesProvider).valueOrNull ?? const <Rate>[];
        expect(stored.single.ratePerUsd, 84.0);
      },
    );

    test(
      'fetches a currency that has no rate, even within the 24h window',
      () async {
        // Regression: the staleness check looked only at the *newest* auto row, so
        // adding a EUR account right after a RUB refresh left EUR unrated — and
        // «Нет курса» on screen — for up to a day.
        final client = _FakeClient({'RUB': 84.0, 'EUR': 0.88});
        final container = _container(
          accounts: InMemoryAccountsRepository([
            _account('RUB'),
            _account('EUR'),
          ]),
          client: client,
          rates: [
            Rate(
              userId: _userId,
              code: 'RUB',
              ratePerUsd: 84.0,
              source: RateSource.auto,
              updatedAt: DateTime.now().toUtc(),
            ),
          ],
        );

        await container.read(rateRefreshProvider.notifier).refreshIfStale();

        expect(client.calls, 1);
        final stored =
            container.read(ratesProvider).valueOrNull ?? const <Rate>[];
        expect({for (final rate in stored) rate.code}, {'RUB', 'EUR'});
      },
    );

    test('a USD account alone does not count as unrated', () async {
      // USD is the pivot and never needs a stored row, so it must not keep
      // re-triggering the fetch.
      final client = _FakeClient({'RUB': 84.0});
      final container = _container(
        accounts: InMemoryAccountsRepository([
          _account('RUB'),
          _account('USD'),
        ]),
        client: client,
        rates: [
          Rate(
            userId: _userId,
            code: 'RUB',
            ratePerUsd: 84.0,
            source: RateSource.auto,
            updatedAt: DateTime.now().toUtc(),
          ),
        ],
      );

      await container.read(rateRefreshProvider.notifier).refreshIfStale();

      expect(client.calls, 0);
    });

    test('a manual rate counts as having a rate', () async {
      final client = _FakeClient({'EUR': 0.88});
      final container = _container(
        accounts: InMemoryAccountsRepository([
          _account('RUB'),
          _account('EUR'),
        ]),
        client: client,
        rates: [
          Rate(
            userId: _userId,
            code: 'RUB',
            ratePerUsd: 84.0,
            source: RateSource.auto,
            updatedAt: DateTime.now().toUtc(),
          ),
          Rate(
            userId: _userId,
            code: 'EUR',
            ratePerUsd: 0.9,
            source: RateSource.manual,
            updatedAt: DateTime.utc(2020, 1, 1),
          ),
        ],
      );

      await container.read(rateRefreshProvider.notifier).refreshIfStale();

      expect(client.calls, 0);
    });

    test('a second call within the throttle window does not refetch', () async {
      final client = _FakeClient({'RUB': 84.0});
      final container = _container(
        accounts: InMemoryAccountsRepository([_account('RUB')]),
        client: client,
      );

      final notifier = container.read(rateRefreshProvider.notifier);
      await notifier.refreshIfStale();
      await notifier.refreshIfStale();

      expect(client.calls, 1);
    });

    test('makes no network call when there are no accounts at all', () async {
      final client = _FakeClient({'RUB': 84.0});
      final container = _container(
        accounts: InMemoryAccountsRepository(const []),
        client: client,
      );

      await container.read(rateRefreshProvider.notifier).refreshIfStale();

      expect(client.calls, 0);
    });
  });
}
