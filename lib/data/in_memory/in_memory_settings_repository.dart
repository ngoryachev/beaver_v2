import '../../domain/models/user_settings.dart';
import '../../domain/repositories/settings_repository.dart';

class InMemorySettingsRepository implements SettingsRepository {
  UserSettings? _settings;

  InMemorySettingsRepository([this._settings]);

  @override
  Future<UserSettings?> get() async => _settings;

  @override
  Future<void> save(UserSettings settings) async {
    _settings = settings;
  }
}
