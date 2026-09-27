import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/rates/rate_fetcher.dart';
import '../../data/services/auth_service.dart';
import '../../data/supabase/supabase_accounts_repository.dart';
import '../../data/supabase/supabase_planned_ops_repository.dart';
import '../../data/supabase/supabase_rates_repository.dart';
import '../../data/supabase/supabase_scenarios_repository.dart';
import '../../data/supabase/supabase_settings_repository.dart';
import '../../domain/repositories/accounts_repository.dart';
import '../../domain/repositories/planned_ops_repository.dart';
import '../../domain/repositories/rates_repository.dart';
import '../../domain/repositories/scenarios_repository.dart';
import '../../domain/repositories/settings_repository.dart';

/// The single Supabase client. Tests never reach this: they override the
/// repository providers below with in-memory ones instead of mocking Supabase.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(supabaseClientProvider));
});

/// Auth events straight from Supabase. Lives here, next to [authServiceProvider],
/// so [currentUserIdProvider] can depend on it without importing the auth
/// controller back.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// Id of the signed-in user, `null` when signed out. Overridden in tests so
/// repositories and settings can be built without an auth session.
///
/// Watches the auth stream: the [AuthService] instance never changes, so without
/// that the id would stay whoever signed in first.
///
/// Every provider holding per-user data watches this and bails out on `null`.
/// That gives two things: signing in as somebody else refetches instead of
/// leaving the previous user's rows on screen, and signed out nothing calls a
/// repository — the Supabase ones dereference `auth.currentUser!`. Re-reading it
/// for the same user returns an equal `String`, so a token refresh does not
/// trigger a reload.
final currentUserIdProvider = Provider<String?>((ref) {
  final authService = ref.watch(authServiceProvider);
  ref.watch(authStateChangesProvider);
  return authService.currentUser?.id;
});

final accountsRepositoryProvider = Provider<AccountsRepository>((ref) {
  return SupabaseAccountsRepository(ref.watch(supabaseClientProvider));
});

final plannedOpsRepositoryProvider = Provider<PlannedOpsRepository>((ref) {
  return SupabasePlannedOpsRepository(ref.watch(supabaseClientProvider));
});

final scenariosRepositoryProvider = Provider<ScenariosRepository>((ref) {
  return SupabaseScenariosRepository(ref.watch(supabaseClientProvider));
});

final ratesRepositoryProvider = Provider<RatesRepository>((ref) {
  return SupabaseRatesRepository(ref.watch(supabaseClientProvider));
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SupabaseSettingsRepository(ref.watch(supabaseClientProvider));
});

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final rateFetcherProvider = Provider<RateFetcher>((ref) {
  return RateFetcher(ref.watch(httpClientProvider));
});
