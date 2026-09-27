import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

class BeaverApp extends ConsumerWidget {
  const BeaverApp({super.key});

  /// The UI is Russian throughout, including the strings Flutter itself
  /// supplies: the date picker, the text-selection menu, tooltips. Without these
  /// delegates `showDatePicker` has no MaterialLocalizations for `ru` and throws
  /// instead of opening.
  ///
  /// Exposed so a test can assert on the configuration the app really installs.
  static const supportedLocales = <Locale>[Locale('ru'), Locale('en')];

  static const localizationsDelegates = <LocalizationsDelegate<Object>>[
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Beaver',
      routerConfig: router,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: supportedLocales,
      localizationsDelegates: localizationsDelegates,
    );
  }

  static ThemeData _theme(Brightness brightness) => ThemeData(
    colorSchemeSeed: const Color(0xFF7A5230),
    brightness: brightness,
    useMaterial3: true,
  );
}
