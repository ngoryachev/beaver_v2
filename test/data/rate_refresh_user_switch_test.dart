import 'dart:convert';

import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/rates/rate_fetcher.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/repositories/accounts_repository.dart';
import 'package:beaver_v2/domain/repositories/rates_repository.dart';
import 'package:beaver_v2/domain/repositories/settings_repository.dart';
import 'package:beaver_v2/domain/models/user_settings.dart';
import 'package:beaver_v2/presentation/providers/rate_refresh_provider.dart';
import 'package:beaver_v2/presentation/providers/rates_provider.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// Every provider holding per-user data watches `currentUserIdProvider` and
// refetches when somebody else signs in — see `user_switch_test.dart`. The rate
// refresh controller holds per-user data too, in plain instance fields, so it
// has to honour the same rule: what it learned about one user's currencies must
// not decide anything for the next one.

/// Stands in for the Supabase session.
final _signedInAs = StateProvider<String?>((ref) => 'user-a');

/// Whoever the scoped repositories below answer as, the way RLS scopes rows.
String? _currentUser;

Account _account(String userId, String code) => Account(
  id: '$userId-$code',
  userId: userId,
  name: code,
  currencyCode: code,
  balance: 100000,
);

class _ScopedAccountsRepository implements AccountsRepository {
  final Map<String, List<Account>> byUser;

  _ScopedAccountsRepository(this.byUser);

  @override
  Future<List<Account>> getAll() async => byUser[_currentUser] ?? const [];

  @override
  Future<void> save(Account account) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> transfer({
    required String fromAccountId,
    required String toAccountId,
    required int fromAmount,
    required int toAmount,
  }) async {}
}

class _ScopedRatesRepository implements RatesRepository {
  final List<Rate> rows;

  _ScopedRatesRepository(this.rows);

  @override
  Future<List<Rate>> getAll() async =>
      rows.where((rate) => rate.userId == _currentUser).toList();

  @override
  Future<void> upsertAll(List<Rate> rates) async {
    for (final rate in rates) {
      rows.removeWhere(
        (existing) =>
            existing.userId == _currentUser && existing.code == rate.code,
      );
      rows.add(
        Rate(
          userId: _currentUser ?? '',
          code: rate.code,
          ratePerUsd: rate.ratePerUsd,
          source: rate.source,
          updatedAt: rate.updatedAt,
        ),
      );
    }
  }

  @override
  Future<void> delete(String code) async => rows.removeWhere(
    (rate) => rate.userId == _currentUser && rate.code == code,
  );
}

class _ScopedSettingsRepository implements SettingsRepository {
  final Map<String, UserSettings> byUser = {};

  @override
  Future<UserSettings?> get() async => byUser[_currentUser];

  @override
  Future<void> save(UserSettings settings) async =>
      byUser[settings.userId] = settings;
}

class _CountingClient extends http.BaseClient {
  final Map<String, double> rates;
  int calls = 0;

  _CountingClient(this.rates);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    final body = jsonEncode({
      'usd': {for (final e in rates.entries) e.key.toLowerCase(): e.value},
    });
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
}

/// The container the tests share: repositories scoped by [_currentUser], the way
/// RLS scopes rows, plus a counting http client.
ProviderContainer _container({
  required _ScopedRatesRepository rates,
  required Map<String, List<Account>> accountsByUser,
  required _CountingClient client,
}) {
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWith((ref) {
        final userId = ref.watch(_signedInAs);
        _currentUser = userId;
        return userId;
      }),
      accountsRepositoryProvider.overrideWithValue(
        _ScopedAccountsRepository(accountsByUser),
      ),
      plannedOpsRepositoryProvider.overrideWithValue(
        InMemoryPlannedOpsRepository(const []),
      ),
      ratesRepositoryProvider.overrideWithValue(rates),
      settingsRepositoryProvider.overrideWithValue(_ScopedSettingsRepository()),
      rateFetcherProvider.overrideWithValue(RateFetcher(client)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Rate _rate(String userId, String code, double perUsd, Duration age) => Rate(
  userId: userId,
  code: code,
  ratePerUsd: perUsd,
  source: RateSource.auto,
  updatedAt: DateTime.now().toUtc().subtract(age),
);

void main() {
  test("another user's rate refresh does not count as this user's", () async {
    final client = _CountingClient({'RUB': 84.0});
    // user-a's rate is stale, so «Обновить сейчас» really fetches; user-b's is
    // three days old and must be refreshed on their first check.
    final rates = _ScopedRatesRepository([
      _rate('user-a', 'RUB', 70.0, const Duration(days: 5)),
      _rate('user-b', 'RUB', 60.0, const Duration(days: 3)),
    ]);
    final container = _container(
      rates: rates,
      accountsByUser: {
        'user-a': [_account('user-a', 'RUB')],
        'user-b': [_account('user-b', 'RUB')],
      },
      client: client,
    );

    // user-a taps «Обновить сейчас» in settings. This sets no throttle
    // timestamp, only the "a fetch just completed" one.
    _currentUser = 'user-a';
    await container.read(rateRefreshProvider.notifier).refreshNow();
    expect(client.calls, 1, reason: 'user-a asked for fresh rates');

    // Somebody else signs in.
    container.read(_signedInAs.notifier).state = 'user-b';
    await container.read(ratesProvider.future);
    expect(
      (container.read(ratesProvider).valueOrNull ?? const <Rate>[])
          .single
          .ratePerUsd,
      60.0,
      reason: 'user-b sees their own stored rate',
    );

    // user-b's own rate is three days old, well past the 24 h window, so their
    // start-up check has to refetch.
    await container.read(rateRefreshProvider.notifier).refreshIfStale();

    expect(
      client.calls,
      2,
      reason:
          'user-b has a three-day-old rate and must get a fresh one; the '
          'refresh user-a triggered must not stand in for theirs',
    );
  });

  test(
    "another user's throttle does not swallow this user's first check",
    () async {
      // The 2 s resume throttle is per-user too: signing in right after somebody
      // else checked must not skip the new user's start-up refresh.
      final client = _CountingClient({'RUB': 84.0});
      final rates = _ScopedRatesRepository([
        _rate('user-a', 'RUB', 70.0, Duration.zero),
        _rate('user-b', 'RUB', 60.0, const Duration(days: 3)),
      ]);
      final container = _container(
        rates: rates,
        accountsByUser: {
          'user-a': [_account('user-a', 'RUB')],
          'user-b': [_account('user-b', 'RUB')],
        },
        client: client,
      );

      // Fresh rate, so this only arms the throttle; it does not fetch.
      _currentUser = 'user-a';
      await container.read(rateRefreshProvider.notifier).refreshIfStale();
      expect(client.calls, 0, reason: "user-a's rate is fresh");

      // Somebody else signs in — well inside the 2 s window.
      container.read(_signedInAs.notifier).state = 'user-b';
      await container.read(ratesProvider.future);
      await container.read(rateRefreshProvider.notifier).refreshIfStale();

      expect(
        client.calls,
        1,
        reason:
            "user-b's three-day-old rate must be refreshed; a check user-a made "
            'moments ago must not throttle theirs',
      );
    },
  );

  test("another user's unfetchable codes do not silence this user", () async {
    // A code neither source knows is remembered so it stops forcing a fetch —
    // but that memory belongs to the user whose currencies it described.
    final client = _CountingClient({'RUB': 84.0}); // knows RUB, never XXX
    final rates = _ScopedRatesRepository([
      // user-b has a fresh RUB rate, so only the unrated XXX can trigger them.
      _rate('user-b', 'RUB', 60.0, Duration.zero),
    ]);
    final container = _container(
      rates: rates,
      accountsByUser: {
        'user-a': [_account('user-a', 'XXX')],
        'user-b': [_account('user-b', 'RUB'), _account('user-b', 'XXX')],
      },
      client: client,
    );

    _currentUser = 'user-a';
    await container.read(rateRefreshProvider.notifier).refreshNow();
    // Counted in rounds, not requests: a source that answers with none of the
    // wanted codes still sends the fallback source its turn, so user-a's single
    // refresh is two calls. What matters is that another one follows.
    final afterUserA = client.calls;
    expect(
      afterUserA,
      greaterThan(0),
      reason: 'user-a asked; XXX came back missing',
    );

    container.read(_signedInAs.notifier).state = 'user-b';
    await container.read(ratesProvider.future);
    await container.read(rateRefreshProvider.notifier).refreshIfStale();

    expect(
      client.calls,
      greaterThan(afterUserA),
      reason:
          'user-b has an unrated XXX of their own; what user-a learned about '
          'XXX must not stand in for asking on their behalf',
    );
  });
}
