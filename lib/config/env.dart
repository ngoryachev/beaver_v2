/// Build-time configuration. Values come from `--dart-define-from-file=.env.json`,
/// so nothing secret lives in the repository.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Whether this build actually carries its Supabase configuration.
  ///
  /// `String.fromEnvironment` defaults to an empty string, so a run without
  /// `--dart-define-from-file=.env.json` compiles fine and only fails deep
  /// inside `Supabase.initialize`, with an error that says nothing about the
  /// missing flag. `deploy_web.sh` guards the deployed path; this guards
  /// `flutter run`.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
