/// Build-time configuration. Values come from `--dart-define-from-file=.env.json`,
/// so nothing secret lives in the repository.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}
