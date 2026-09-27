import 'dart:convert';

import 'package:beaver_v2/data/rates/rate_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Answers each URL from a canned map. Supabase and the real rate APIs are never
/// contacted; only the fetcher's own branching is under test.
class _FakeClient extends http.BaseClient {
  final Map<String, http.Response> responses;
  final List<String> requested = [];

  _FakeClient(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();
    requested.add(url);
    final response = responses[url];
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
    'date': '2026-03-01',
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

void main() {
  group('RateFetcher', () {
    test('uses the primary source when it answers', () async {
      final client = _FakeClient({
        RateFetcher.primaryUrl: _primaryOk({'RUB': 90.5, 'EUR': 0.92}),
      });

      final rates = await RateFetcher(client).fetch(['RUB', 'EUR']);

      expect(rates, {'RUB': 90.5, 'EUR': 0.92});
      expect(client.requested, [RateFetcher.primaryUrl]);
    });

    test(
      'falls back to the second source when the primary errors out',
      () async {
        final client = _FakeClient({
          // The primary URL is absent, so the fake throws a ClientException.
          RateFetcher.fallbackUrl: _fallbackOk({'RUB': 91.0, 'KZT': 500.0}),
        });

        final rates = await RateFetcher(client).fetch(['RUB', 'KZT']);

        expect(rates, {'RUB': 91.0, 'KZT': 500.0});
        expect(client.requested, [
          RateFetcher.primaryUrl,
          RateFetcher.fallbackUrl,
        ]);
      },
    );

    test('falls back when the primary returns a non-200 status', () async {
      final client = _FakeClient({
        RateFetcher.primaryUrl: http.Response('gateway timeout', 504),
        RateFetcher.fallbackUrl: _fallbackOk({'RUB': 91.0}),
      });

      final rates = await RateFetcher(client).fetch(['RUB']);

      expect(rates, {'RUB': 91.0});
      expect(client.requested, [
        RateFetcher.primaryUrl,
        RateFetcher.fallbackUrl,
      ]);
    });

    test('falls back when the primary returns unparseable JSON', () async {
      final client = _FakeClient({
        RateFetcher.primaryUrl: http.Response('<html>502</html>', 200),
        RateFetcher.fallbackUrl: _fallbackOk({'RUB': 91.0}),
      });

      final rates = await RateFetcher(client).fetch(['RUB']);

      expect(rates, {'RUB': 91.0});
    });

    test(
      'falls back when the primary JSON lacks the expected section',
      () async {
        final client = _FakeClient({
          RateFetcher.primaryUrl: http.Response(
            jsonEncode({'date': '2026-03-01'}),
            200,
          ),
          RateFetcher.fallbackUrl: _fallbackOk({'RUB': 91.0}),
        });

        final rates = await RateFetcher(client).fetch(['RUB']);

        expect(rates, {'RUB': 91.0});
      },
    );

    test(
      'falls back when the primary knows none of the requested codes',
      () async {
        final client = _FakeClient({
          RateFetcher.primaryUrl: _primaryOk({'EUR': 0.92}),
          RateFetcher.fallbackUrl: _fallbackOk({'KZT': 500.0}),
        });

        final rates = await RateFetcher(client).fetch(['KZT']);

        expect(rates, {'KZT': 500.0});
      },
    );

    test('throws when both sources fail', () async {
      final client = _FakeClient(const {});

      await expectLater(
        () => RateFetcher(client).fetch(['RUB']),
        throwsA(isA<RateFetchException>()),
      );
      // Both sources were attempted before giving up.
      expect(client.requested, [
        RateFetcher.primaryUrl,
        RateFetcher.fallbackUrl,
      ]);
    });

    test('requests only the codes it was asked for', () async {
      final client = _FakeClient({
        RateFetcher.primaryUrl: _primaryOk({
          'RUB': 90.5,
          'EUR': 0.92,
          'JPY': 150.0,
          'KZT': 500.0,
        }),
      });

      final rates = await RateFetcher(client).fetch(['RUB', 'JPY']);

      expect(rates.keys, unorderedEquals(['RUB', 'JPY']));
    });

    test('drops USD and blank codes before hitting the network', () async {
      final client = _FakeClient(const {});

      expect(await RateFetcher(client).fetch(['USD', '', '  ']), isEmpty);
      expect(client.requested, isEmpty);
    });

    test('an empty request list makes no call at all', () async {
      final client = _FakeClient(const {});

      expect(await RateFetcher(client).fetch(const []), isEmpty);
      expect(client.requested, isEmpty);
    });

    test('ignores non-positive and non-numeric values', () async {
      final client = _FakeClient({
        RateFetcher.primaryUrl: http.Response(
          jsonEncode({
            'usd': {'rub': 0, 'eur': -1, 'kzt': 'нет данных', 'gel': 2.7},
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      });

      final rates = await RateFetcher(
        client,
      ).fetch(['RUB', 'EUR', 'KZT', 'GEL']);

      expect(rates, {'GEL': 2.7});
    });

    test('is case-insensitive about requested codes', () async {
      final client = _FakeClient({
        RateFetcher.primaryUrl: _primaryOk({'RUB': 90.5}),
      });

      final rates = await RateFetcher(client).fetch(['rub']);

      expect(rates, {'RUB': 90.5});
    });
  });
}
