import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fetches USD-based exchange rates from a public API.
///
/// Two sources are tried in order: a CDN-hosted dataset first (no key, generous
/// limits), then a second provider if it is unreachable or malformed. The client
/// is injected so tests can drive both paths without network access.
class RateFetcher {
  /// Primary source: `{"usd": {"rub": 90.1, ...}}` with lowercase codes.
  static const primaryUrl =
      'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json';

  /// Fallback source: `{"result": "success", "rates": {"RUB": 90.1, ...}}`.
  static const fallbackUrl = 'https://open.er-api.com/v6/latest/USD';

  final http.Client _client;

  RateFetcher(this._client);

  /// Rates per USD for [codes], keyed by upper-case code.
  ///
  /// Only the requested codes are returned — the APIs ship ~200 currencies and
  /// storing all of them per user would be pointless. USD is always 1 and needs
  /// no lookup.
  ///
  /// The fallback is whole-source, not per-code: the first source that answers
  /// with anything wins, so a code missing from an otherwise useful primary
  /// response is absent from the result without the secondary being asked. Any
  /// code that ends up absent is reported as missing rather than stored with a
  /// wrong value.
  ///
  /// Throws [RateFetchException] only when *both* sources fail. A source that
  /// answers but lists none of [codes] yields an empty map, which is a fact
  /// about those currencies, not a failure to reach the network.
  Future<Map<String, double>> fetch(Iterable<String> codes) async {
    final wanted = {
      for (final code in codes)
        if (code.trim().isNotEmpty) code.toUpperCase(),
    }..remove('USD');
    if (wanted.isEmpty) return const {};

    var anyAnswered = false;
    for (final source in [_fetchPrimary, _fetchFallback]) {
      final rates = await _tryFetch(source, wanted);
      if (rates == null) continue; // This source failed; try the next.
      anyAnswered = true;
      if (rates.isNotEmpty) return rates;
    }

    // A source answered but lists none of these codes. That is not a failure:
    // the caller has to see them absent — which is how they end up in
    // `missingRateCodes` and stop forcing a refetch — rather than an exception.
    if (anyAnswered) return const {};

    throw const RateFetchException('Не удалось получить курсы валют');
  }

  /// Runs one source. `null` means it failed — network error, non-200, bad JSON,
  /// unexpected shape are all equivalent here. An empty map is a different
  /// answer: the source replied and simply knows none of [wanted].
  Future<Map<String, double>?> _tryFetch(
    Future<Map<String, double>> Function(Set<String>) source,
    Set<String> wanted,
  ) async {
    try {
      return await source(wanted);
    } on Object {
      return null;
    }
  }

  Future<Map<String, double>> _fetchPrimary(Set<String> wanted) async {
    final body = await _getJson(primaryUrl);
    final table = body['usd'];
    if (table is! Map) throw const FormatException('Нет секции "usd"');
    return _pick(wanted, (code) => table[code.toLowerCase()]);
  }

  Future<Map<String, double>> _fetchFallback(Set<String> wanted) async {
    final body = await _getJson(fallbackUrl);
    final table = body['rates'];
    if (table is! Map) throw const FormatException('Нет секции "rates"');
    return _pick(wanted, (code) => table[code.toUpperCase()]);
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', Uri.parse(url));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Ожидался JSON-объект');
    }
    return decoded;
  }

  /// Keeps only positive finite numbers: a zero or negative rate would make every
  /// conversion through it nonsense.
  Map<String, double> _pick(
    Set<String> wanted,
    Object? Function(String code) lookup,
  ) {
    final result = <String, double>{};
    for (final code in wanted) {
      final value = lookup(code);
      if (value is num && value > 0 && value.isFinite) {
        result[code] = value.toDouble();
      }
    }
    return result;
  }
}

class RateFetchException implements Exception {
  final String message;

  const RateFetchException(this.message);

  @override
  String toString() => message;
}
