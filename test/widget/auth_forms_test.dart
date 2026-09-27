import 'package:beaver_v2/app.dart';
import 'package:beaver_v2/presentation/screens/auth/login_screen.dart';
import 'package:beaver_v2/presentation/screens/auth/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Form validation only. A valid form calls Supabase, which these tests never
/// do — everything asserted here happens before the network is touched.
Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: BeaverApp.supportedLocales,
        localizationsDelegates: BeaverApp.localizationsDelegates,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('LoginScreen', () {
    testWidgets('refuses an empty form', (tester) async {
      await _pump(tester, const LoginScreen());

      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle();

      expect(find.text('Введите почту'), findsOneWidget);
      expect(find.text('Введите пароль'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('refuses an address without @', (tester) async {
      await _pump(tester, const LoginScreen());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Почта'),
        'нетсобаки',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Пароль'),
        'secret1',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle();

      expect(find.text('Введите корректную почту'), findsOneWidget);
    });
  });

  group('RegisterScreen', () {
    testWidgets('refuses a password shorter than six characters', (
      tester,
    ) async {
      await _pump(tester, const RegisterScreen());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Почта'),
        'a@b.c',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Пароль'),
        '12345',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Повторите пароль'),
        '12345',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Создать аккаунт'));
      await tester.pumpAndSettle();

      expect(find.text('Пароль не короче 6 символов'), findsOneWidget);
    });

    testWidgets('refuses a mismatched confirmation', (tester) async {
      await _pump(tester, const RegisterScreen());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Почта'),
        'a@b.c',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Пароль'),
        'secret1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Повторите пароль'),
        'secret2',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Создать аккаунт'));
      await tester.pumpAndSettle();

      expect(find.text('Пароли не совпадают'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
