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
import 'package:beaver_v2/presentation/providers/auth_providers.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/screens/auth/login_screen.dart';
import 'package:beaver_v2/presentation/screens/auth/register_screen.dart';
import 'package:beaver_v2/presentation/screens/home/home_screen.dart';
import 'package:beaver_v2/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';

/// The router gates the whole app on the auth state: signed out, every screen
/// has to end up on the login form, and signing out while inside must not leave
/// a signed-in screen on display. Nothing else exercises `router.dart`.
const _userId = 'u1';

/// Drives [isAuthenticatedProvider] from the test.
final _signedIn = StateProvider<bool>((ref) => false);

/// Answers the rate API with an empty but valid response, so the refresh the
/// shell kicks off never reaches the network.
class _OfflineClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'usd': <String, double>{}}))),
        200,
      );
}

Future<GoRouter> _pumpApp(WidgetTester tester, {required bool signedIn}) async {
  late final GoRouter router;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        _signedIn.overrideWith((ref) => signedIn),
        // The real one reaches Supabase; the router only needs the boolean.
        isAuthenticatedProvider.overrideWith((ref) => ref.watch(_signedIn)),
        currentUserIdProvider.overrideWith(
          (ref) => ref.watch(_signedIn) ? _userId : null,
        ),
        accountsRepositoryProvider.overrideWithValue(
          InMemoryAccountsRepository([
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
        ratesRepositoryProvider.overrideWithValue(
          InMemoryRatesRepository([
            Rate(
              userId: _userId,
              code: 'RUB',
              ratePerUsd: 90,
              source: RateSource.auto,
              updatedAt: DateTime.now().toUtc(),
            ),
          ]),
        ),
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(
            UserSettings(userId: _userId, baseCurrency: 'RUB'),
          ),
        ),
        rateFetcherProvider.overrideWithValue(RateFetcher(_OfflineClient())),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          router = ref.watch(routerProvider);
          return const BeaverApp();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('signed out', () {
    testWidgets('the home route redirects to the login screen', (tester) async {
      final router = await _pumpApp(tester, signedIn: false);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        Routes.login,
      );
    });

    testWidgets('the register route is reachable without a session', (
      tester,
    ) async {
      final router = await _pumpApp(tester, signedIn: false);

      router.go(Routes.register);
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsOneWidget);
    });

    testWidgets('a protected route redirects instead of rendering', (
      tester,
    ) async {
      final router = await _pumpApp(tester, signedIn: false);

      router.go(Routes.settings);
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        Routes.login,
      );
    });
  });

  group('signed in', () {
    testWidgets('the home screen renders', (tester) async {
      await _pumpApp(tester, signedIn: true);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('the login route redirects back home', (tester) async {
      final router = await _pumpApp(tester, signedIn: true);

      router.go(Routes.login);
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.uri.path, Routes.home);
    });
  });

  testWidgets('signing out from inside the app lands on the login screen', (
    tester,
  ) async {
    late final WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _signedIn.overrideWith((ref) => true),
          isAuthenticatedProvider.overrideWith((ref) => ref.watch(_signedIn)),
          currentUserIdProvider.overrideWith(
            (ref) => ref.watch(_signedIn) ? _userId : null,
          ),
          accountsRepositoryProvider.overrideWithValue(
            InMemoryAccountsRepository(const []),
          ),
          plannedOpsRepositoryProvider.overrideWithValue(
            InMemoryPlannedOpsRepository(const []),
          ),
          scenariosRepositoryProvider.overrideWithValue(
            InMemoryScenariosRepository([
              Scenario(id: 's1', userId: _userId, name: 'Все', isDefault: true),
            ]),
          ),
          ratesRepositoryProvider.overrideWithValue(
            InMemoryRatesRepository(const []),
          ),
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              UserSettings(userId: _userId, baseCurrency: 'RUB'),
            ),
          ),
          rateFetcherProvider.overrideWithValue(RateFetcher(_OfflineClient())),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const BeaverApp();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    // What `AuthService.signOut` ultimately does to the auth state.
    capturedRef.read(_signedIn.notifier).state = false;
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });
}
