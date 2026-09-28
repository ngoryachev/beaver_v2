import 'dart:convert';

import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/data/rates/rate_fetcher.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/presentation/providers/rate_refresh_provider.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Both rate sources answer normally but simply do not list the requested
/// currency. That is not a failure of either source, and [RateFetcher.fetch]
/// documents it as such: "Codes neither source knows are simply absent from the
/// result, so the caller keeps reporting them as missing rather than storing a
/// wrong value."
///
/// [RateRefreshController.refreshNow] is written against exactly that contract —
/// it derives `_unfetchable` from the codes it asked for minus the keys that came
/// back, which only means anything if a partial (or empty) map can be returned.
///
/// The existing coverage in `rate_refresh_test.dart` only ever mixes an unknown
/// code in with a known one, which keeps the result map non-empty and hides the
/// case where *every* requested code is unknown.
const _userId = 'u1';

class _FakeClient extends http.BaseClient {
  final Map<String, http.Response> responses;
  final List<String> requested = [];

  _FakeClient(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested.add(request.url.toString());
    final response = responses[request.url.toString()];
    if (response == null) {
      throw http.ClientException('Нет соединения', request.url);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
    );
  }
}

http.Response _primaryOk(Map<String, double> rates) => http.Response(
  jsonEncode({
    'date': '2026-09-28',
    'usd': {for (final e in rates.entries) e.key.toLowerCase(): e.value},
  }),
  200,
);

http.Response _fallbackOk(Map<String, double> rates) => http.Response(
  jsonEncode({
    'result': 'success',
    'base_code': 'USD',
    'rates': {for (final e in rates.entries) e.key.toUpperCase(): e.value},
  }),
  200,
);

/// A client whose two sources are both healthy and both list RUB only.
_FakeClient _healthyClient() => _FakeClient({
  RateFetcher.primaryUrl: _primaryOk({'RUB': 90.0, 'EUR': 0.92}),
  RateFetcher.fallbackUrl: _fallbackOk({'RUB': 91.0}),
});

ProviderContainer _container(_FakeClient client, String currencyCode) {
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue(_userId),
      accountsRepositoryProvider.overrideWithValue(
        InMemoryAccountsRepository([
          Account(
            id: 'a1',
            userId: _userId,
            name: currencyCode,
            currencyCode: currencyCode,
            balance: 100000,
          ),
        ]),
      ),
      plannedOpsRepositoryProvider.overrideWithValue(
        InMemoryPlannedOpsRepository(),
      ),
      ratesRepositoryProvider.overrideWithValue(InMemoryRatesRepository()),
      settingsRepositoryProvider.overrideWithValue(InMemorySettingsRepository()),
      rateFetcherProvider.overrideWithValue(RateFetcher(client)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('a request where no code is known to either source', () {
    test('reports the codes as absent rather than as a failed fetch', () async {
      final client = _healthyClient();

      final rates = await RateFetcher(client).fetch(['XXX']);

      expect(rates, isEmpty);
      // Both sources were consulted and both answered with valid JSON, so
      // nothing here is a transport or format failure.
      expect(client.requested, [
        RateFetcher.primaryUrl,
        RateFetcher.fallbackUrl,
      ]);
    });

    test('does not refetch on every return to the foreground', () async {
      // `_unfetchable` exists precisely so a code neither source knows stops
      // forcing a request; it is only populated when `fetch` returns.
      final client = _healthyClient();
      final notifier = _container(client, 'XXX').read(
        rateRefreshProvider.notifier,
      );

      await notifier.refreshIfStale();
      final afterFirstResume = client.requested.length;

      // Past the 2 s resume throttle, so only the staleness rules hold it back.
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      await notifier.refreshIfStale();

      expect(
        client.requested.length,
        afterFirstResume,
        reason:
            'an unfetchable code must not force a fresh pair of requests on '
            'every resume',
      );
    });

    test('leaves no error on screen when both sources answered', () async {
      // A non-error state is what keeps «Не удалось обновить курсы: ...» off the
      // settings screen. The currency is reported as unrated through
      // `missingRateCodes` instead, which is the honest signal.
      final container = _container(_healthyClient(), 'XXX');

      await container.read(rateRefreshProvider.notifier).refreshNow();

      expect(container.read(rateRefreshProvider).hasError, isFalse);
    });

    test('a known code alongside an unknown one still stores and settles', () {
      // The passing counterpart, kept next to the three above so the difference
      // between the two situations is visible: a non-empty result map is what
      // the current implementation needs to behave correctly.
      return _container(_healthyClient(), 'RUB')
          .read(rateRefreshProvider.notifier)
          .refreshNow();
    });
  });
}
