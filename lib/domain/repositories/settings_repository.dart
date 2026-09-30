import '../models/user_settings.dart';

abstract class SettingsRepository {
  /// The current user's settings, or `null` when nothing has been saved yet.
  Future<UserSettings?> get();

  Future<void> save(UserSettings settings);
}
