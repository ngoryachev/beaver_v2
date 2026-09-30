import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/scenario.dart';
import 'package:beaver_v2/domain/models/user_settings.dart';
import 'package:beaver_v2/domain/repositories/accounts_repository.dart';
import 'package:beaver_v2/domain/repositories/scenarios_repository.dart';
import 'package:beaver_v2/domain/repositories/settings_repository.dart';
import 'package:beaver_v2/presentation/providers/accounts_provider.dart';
import 'package:beaver_v2/presentation/providers/ops_provider.dart';
import 'package:beaver_v2/presentation/providers/rates_provider.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/providers/scenarios_provider.dart';
import 'package:beaver_v2/presentation/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the Supabase session so a test can sign out and back in.
final _signedInAs = StateProvider<String?>((ref) => 'user-a');

/// Bumped to make `currentUserIdProvider` recompute without the user changing —
/// what a Supabase `tokenRefreshed` event does.
final _authEvents = StateProvider<int>((ref) => 0);

/// Whoever the fake repositories below should answer as. Set by the container's
/// override, mirroring how the real repositories read `auth.currentUser`.
String? _currentUser;

Account _account(String userId, String name) => Account(
  id: '$userId-1',
  userId: userId,
  name: name,
  currencyCode: 'RUB',
  balance: 100000,
);

/// Returns only the current user's rows, the way RLS does server-side.
class _ScopedAccountsRepository implements AccountsRepository {
  final Map<String, List<Account>> byUser;
  int loads = 0;

  _ScopedAccountsRepository(this.byUser);

  @override
  Future<List<Account>> getAll() async {
    loads++;
    return byUser[_currentUser] ?? const [];
  }

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

class _ScopedScenariosRepository implements ScenariosRepository {
  final List<Scenario> rows = [];

  @override
  Future<List<Scenario>> getAll() async =>
      rows.where((scenario) => scenario.userId == _currentUser).toList();

  @override
  Future<void> save(Scenario scenario) async {
    rows
      ..removeWhere((existing) => existing.id == scenario.id)
      ..add(scenario);
  }

  @override
  Future<void> delete(String id) async =>
      rows.removeWhere((scenario) => scenario.id == id);
}

class _ScopedSettingsRepository implements SettingsRepository {
  final Map<String, UserSettings> byUser = {};

  @override
  Future<UserSettings?> get() async => byUser[_currentUser];

  @override
  Future<void> save(UserSettings settings) async =>
      byUser[settings.userId] = settings;
}

void main() {
  group('signing out and back in as somebody else', () {
    late _ScopedAccountsRepository accounts;
    late ProviderContainer container;

    setUp(() {
      _currentUser = 'user-a';
      accounts = _ScopedAccountsRepository({
        'user-a': [_account('user-a', 'Карта Ани')],
        'user-b': [_account('user-b', 'Карта Бори')],
      });
      container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWith((ref) {
            ref.watch(_authEvents);
            final userId = ref.watch(_signedInAs);
            _currentUser = userId;
            return userId;
          }),
          accountsRepositoryProvider.overrideWithValue(accounts),
          scenariosRepositoryProvider.overrideWithValue(
            _ScopedScenariosRepository(),
          ),
          plannedOpsRepositoryProvider.overrideWithValue(
            InMemoryPlannedOpsRepository(const []),
          ),
          ratesRepositoryProvider.overrideWithValue(
            InMemoryRatesRepository(const []),
          ),
          settingsRepositoryProvider.overrideWithValue(
            _ScopedSettingsRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
    });

    test("the next user never sees the previous one's accounts", () async {
      expect(
        (await container.read(accountsProvider.future)).single.name,
        'Карта Ани',
      );

      container.read(_signedInAs.notifier).state = 'user-b';

      expect(
        (await container.read(accountsProvider.future)).single.name,
        'Карта Бори',
        reason: 'the accounts must be refetched for the new user',
      );
    });

    test('signing out empties the data without hitting the repository', () async {
      await container.read(accountsProvider.future);
      final loadsWhileSignedIn = accounts.loads;

      container.read(_signedInAs.notifier).state = null;

      expect(await container.read(accountsProvider.future), isEmpty);
      // A signed-out repository call would dereference a null Supabase session.
      expect(accounts.loads, loadsWhileSignedIn);
    });

    test('every per-user provider empties on sign-out', () async {
      await container.read(accountsProvider.future);
      await container.read(opsProvider.future);
      await container.read(ratesProvider.future);
      await container.read(scenariosProvider.future);
      await container.read(settingsProvider.future);

      container.read(_signedInAs.notifier).state = null;

      expect(await container.read(accountsProvider.future), isEmpty);
      expect(await container.read(opsProvider.future), isEmpty);
      expect(await container.read(ratesProvider.future), isEmpty);
      expect(await container.read(scenariosProvider.future), isEmpty);
      expect(await container.read(settingsProvider.future), isNull);
    });

    test('a token refresh does not reload the data', () async {
      // Supabase re-emits an auth event on every token refresh. The id is then
      // recomputed, but it is an equal String, so nothing downstream should see
      // a change — otherwise the app would refetch everything about hourly.
      await container.read(accountsProvider.future);
      final loadsBefore = accounts.loads;

      for (var i = 0; i < 3; i++) {
        container.read(_authEvents.notifier).state = i + 1;
        await container.read(accountsProvider.future);
      }

      expect(accounts.loads, loadsBefore);
    });

    test('the default scenario is created per user, not shared', () async {
      final forA = await container.read(scenariosProvider.future);
      expect(forA.single.userId, 'user-a');

      container.read(_signedInAs.notifier).state = 'user-b';

      final forB = await container.read(scenariosProvider.future);
      expect(forB.single.userId, 'user-b');
    });

    test('settings are recreated for the new user', () async {
      final forA = await container.read(settingsProvider.future);
      expect(forA?.userId, 'user-a');

      container.read(_signedInAs.notifier).state = 'user-b';

      final forB = await container.read(settingsProvider.future);
      expect(forB?.userId, 'user-b');
    });
  });
}
