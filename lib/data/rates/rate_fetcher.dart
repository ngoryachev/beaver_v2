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
  /// no lookup. Codes neither source knows are simply absent from the result, so
  /// the caller keeps reporting them as missing rather than storing a wrong value.
  Future<Map<String, double>> fetch(Iterable<String> codes) async {
    final wanted = {
      for (final code in codes)
        if (code.trim().isNotEmpty) code.toUpperCase(),
    }..remove('USD');
    if (wanted.isEmpty) return const {};

    final fromPrimary = await _tryFetch(_fetchPrimary, wanted);
    if (fromPrimary != null) return fromPrimary;

    final fromFallback = await _tryFetch(_fetchFallback, wanted);
    if (fromFallback != null) return fromFallback;

    throw const RateFetchException('Не удалось получить курсы валют');
  }

  /// Runs one source, swallowing its failure so the next can be tried.
  Future<Map<String, double>?> _tryFetch(
    Future<Map<String, double>> Function(Set<String>) source,
    Set<String> wanted,
  ) async {
    try {
      final rates = await source(wanted);
      return rates.isEmpty ? null : rates;
    } on Object {
      // Network error, non-200, bad JSON, unexpected shape — all equivalent here:
      // this source produced nothing usable, so fall through to the next one.
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
