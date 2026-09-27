import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repo_providers.dart';

/// Whether somebody is signed in right now.
///
/// Reads the session synchronously — a restored session is available before the
/// first auth event arrives, so the router must not wait for the stream.
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authService = ref.watch(authServiceProvider);
  // Depend on the stream so a sign-in or sign-out recomputes this.
  ref.watch(authStateChangesProvider);
  return authService.isAuthenticated;
});

/// Sign-in / sign-up / sign-out, with the pending and error state the auth
/// screens render.
class AuthController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<bool> signIn(String email, String password) => _run(
    () =>
        ref.read(authServiceProvider).signIn(email: email, password: password),
  );

  Future<bool> signUp(String email, String password) => _run(
    () =>
        ref.read(authServiceProvider).signUp(email: email, password: password),
  );

  Future<bool> signOut() => _run(() => ref.read(authServiceProvider).signOut());

  void clearError() {
    if (state.hasError) state = const AsyncValue.data(null);
  }

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncValue.loading();
    try {
      await action();
      state = const AsyncValue.data(null);
      return true;
    } on AuthException catch (error, stack) {
      state = AsyncValue.error(_translate(error), stack);
      return false;
    } catch (error, stack) {
      state = AsyncValue.error(_translate(error), stack);
      return false;
    }
  }

  /// Supabase reports errors in English; the UI is Russian throughout.
  static String _translate(Object error) {
    final message = error is AuthException ? error.message : error.toString();
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return 'Неверная почта или пароль';
    }
    if (lower.contains('user already registered') ||
        lower.contains('already been registered')) {
      return 'Пользователь с такой почтой уже зарегистрирован';
    }
    if (lower.contains('password should be at least')) {
      return 'Пароль должен быть не короче 6 символов';
    }
    if (lower.contains('email not confirmed')) {
      return 'Почта не подтверждена';
    }
    if (lower.contains('failed host lookup') ||
        lower.contains('socketexception') ||
        lower.contains('clientexception')) {
      return 'Нет связи с сервером';
    }
    return message;
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AsyncValue<void>>(AuthController.new);
