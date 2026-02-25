import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/app_settings.dart';

class SettingsService {
  static const _keyServerUrl = 'server_url';
  static const _keyOnboardingComplete = 'onboarding_complete';
  static const _keyDarkMode = 'dark_mode';
  static const _keyTheme = 'selected_theme';
  static const _keyVibration = 'vibration_enabled';
  static const _keyAlertVolume = 'alert_volume';
  static const _keyMonitoringRoomIds = 'monitoring_room_ids';
  static const _keyActiveListeningRoomId = 'active_listening_room_id';

  final FlutterSecureStorage _storage;

  SettingsService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  Future<AppSettings> load() async {
    final serverUrl = await _storage.read(key: _keyServerUrl);
    final onboardingStr = await _storage.read(key: _keyOnboardingComplete);
    final darkModeStr = await _storage.read(key: _keyDarkMode);
    final theme = await _storage.read(key: _keyTheme);
    final vibrationStr = await _storage.read(key: _keyVibration);
    final volumeStr = await _storage.read(key: _keyAlertVolume);

    return AppSettings(
      serverUrl: serverUrl,
      onboardingComplete: onboardingStr == 'true',
      darkModeEnabled: darkModeStr != 'false',
      selectedTheme: theme ?? 'warm',
      vibrationEnabled: vibrationStr != 'false',
      alertVolume: volumeStr != null ? double.tryParse(volumeStr) ?? 0.5 : 0.5,
    );
  }

  Future<void> save(AppSettings settings) async {
    await Future.wait([
      _storage.write(key: _keyServerUrl, value: settings.serverUrl ?? ''),
      _storage.write(
        key: _keyOnboardingComplete,
        value: settings.onboardingComplete.toString(),
      ),
      _storage.write(
        key: _keyDarkMode,
        value: settings.darkModeEnabled.toString(),
      ),
      _storage.write(key: _keyTheme, value: settings.selectedTheme),
      _storage.write(
        key: _keyVibration,
        value: settings.vibrationEnabled.toString(),
      ),
      _storage.write(
        key: _keyAlertVolume,
        value: settings.alertVolume.toString(),
      ),
    ]);
  }

  Future<void> saveServerUrl(String url) async {
    await _storage.write(key: _keyServerUrl, value: url);
  }

  Future<void> markOnboardingComplete() async {
    await _storage.write(key: _keyOnboardingComplete, value: 'true');
  }

  Future<Set<int>> loadMonitoringRoomIds() async {
    final raw = await _storage.read(key: _keyMonitoringRoomIds);
    if (raw == null || raw.isEmpty) return {};
    return raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
  }

  Future<void> saveMonitoringRoomIds(Set<int> ids) async {
    await _storage.write(key: _keyMonitoringRoomIds, value: ids.join(','));
  }

  Future<int?> loadActiveListeningRoomId() async {
    final raw = await _storage.read(key: _keyActiveListeningRoomId);
    if (raw == null || raw.trim().isEmpty) return null;
    return int.tryParse(raw.trim());
  }

  Future<void> saveActiveListeningRoomId(int? roomId) async {
    if (roomId == null) {
      await _storage.delete(key: _keyActiveListeningRoomId);
      return;
    }
    await _storage.write(key: _keyActiveListeningRoomId, value: '$roomId');
  }
}
