import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'presentation/providers/auth_providers.dart';
import 'presentation/providers/rate_refresh_provider.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/register_screen.dart';
import 'presentation/screens/forecast/forecast_screen.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/ops/op_edit_screen.dart';
import 'presentation/screens/scenarios/scenario_edit_screen.dart';
import 'presentation/screens/scenarios/scenarios_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';

/// Route paths, in one place so screens can navigate without string literals.
abstract final class Routes {
  static const login = '/login';
  static const register = '/register';
  static const home = '/';
  static const opEdit = '/ops/edit';
  static const forecast = '/forecast';
  static const scenarios = '/scenarios';
  static const scenarioEdit = '/scenarios/edit';
  static const settings = '/settings';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.home,
    // Rebuilding the router on every auth event would drop the navigation stack,
    // so the redirect is re-evaluated through a Listenable instead.
    refreshListenable: _AuthRefreshNotifier(ref),
    redirect: (context, state) {
      final isAuthenticated = ref.read(isAuthenticatedProvider);
      final isAuthRoute =
          state.matchedLocation == Routes.login ||
          state.matchedLocation == Routes.register;

      if (!isAuthenticated) return isAuthRoute ? null : Routes.login;
      // Signed in: the auth screens have nothing left to do.
      return isAuthRoute ? Routes.home : null;
    },
    routes: [
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      ShellRoute(
        // Rates are refreshed for the signed-in part of the app only; the login
        // screen has no user and therefore no currencies to fetch.
        builder: (context, state, child) => RateRefreshScope(child: child),
        routes: [
          GoRoute(
            path: Routes.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: Routes.opEdit,
            builder: (context, state) =>
                OpEditScreen(opId: state.extra as String?),
          ),
          GoRoute(
            path: Routes.forecast,
            builder: (context, state) => const ForecastScreen(),
          ),
          GoRoute(
            path: Routes.scenarios,
            builder: (context, state) => const ScenariosScreen(),
          ),
          GoRoute(
            path: Routes.scenarioEdit,
            builder: (context, state) =>
                ScenarioEditScreen(scenarioId: state.extra as String?),
          ),
          GoRoute(
            path: Routes.settings,
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

/// Bridges Riverpod's auth state to go_router's `refreshListenable`.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(isAuthenticatedProvider, (_, __) => notifyListeners());
  }
}
