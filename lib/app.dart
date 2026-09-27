import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

class BeaverApp extends ConsumerWidget {
  const BeaverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Beaver',
      routerConfig: router,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      debugShowCheckedModeBanner: false,
    );
  }

  static ThemeData _theme(Brightness brightness) => ThemeData(
    colorSchemeSeed: const Color(0xFF7A5230),
    brightness: brightness,
    useMaterial3: true,
  );
}
