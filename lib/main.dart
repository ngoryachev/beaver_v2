import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Russian month names and number grouping come from here; without it `intl`
  // only knows `en_US` and every formatted date would be English.
  initializeDateFormatting('ru');

  if (!Env.isConfigured) {
    throw StateError(
      'Не задана конфигурация Supabase. Запускайте с '
      '--dart-define-from-file=.env.json — скопируйте .env.json.example '
      'и впишите SUPABASE_ANON_KEY (см. README).',
    );
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    // `publishableKey` is the current name for what self-hosted Supabase still
    // calls the anon key; `anonKey` is the deprecated spelling of the same thing.
    publishableKey: Env.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: BeaverApp()));
}
