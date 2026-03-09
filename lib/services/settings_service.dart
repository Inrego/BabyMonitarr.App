import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/app_settings.dart';
import '../utils/audio_level_scale.dart';

class SettingsService {
  static const _keyServerUrl = 'server_url';
  static const _keyOnboardingComplete = 'onboarding_complete';
  static const _keyVibration = 'vibration_enabled';
  static const _keyAlertVolume = 'alert_volume';
  static const _keyMonitoringRoomIds = 'monitoring_room_ids';
  static const _keyActiveListeningRoomId = 'active_listening_room_id';
  static const _keyActiveListeningRoomIds = 'active_listening_room_ids';
  static const _keyKeepScreenOn = 'keep_screen_on';
  static const _keyHasSeenKeepScreenOnTip = 'has_seen_keep_screen_on_tip';
  static const _keyApiKey = 'api_key';
  static const _keyApiKeyPrefix = 'api_key_prefix';

  final FlutterSecureStorage _storage;

  SettingsService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  Future<AppSettings> load() async {
    final serverUrl = await _storage.read(key: _keyServerUrl);
    final onboardingStr = await _storage.read(key: _keyOnboardingComplete);
    final vibrationStr = await _storage.read(key: _keyVibration);
    final volumeStr = await _storage.read(key: _keyAlertVolume);
    final keepScreenOnStr = await _storage.read(key: _keyKeepScreenOn);
    final hasSeenTipStr = await _storage.read(key: _keyHasSeenKeepScreenOnTip);
    final apiKey = await _storage.read(key: _keyApiKey);
    final apiKeyPrefix = await _storage.read(key: _keyApiKeyPrefix);

    return AppSettings(
      serverUrl: serverUrl,
      apiKey: apiKey,
      apiKeyPrefix: apiKeyPrefix,
      onboardingComplete: onboardingStr == 'true',
      vibrationEnabled: vibrationStr != 'false',
      alertVolume: _parseAlertVolume(volumeStr),
      keepScreenOn: keepScreenOnStr == 'true',
      hasSeenKeepScreenOnTip: hasSeenTipStr == 'true',
    );
  }

  double _parseAlertVolume(String? rawValue) {
    final parsed = rawValue == null ? null : double.tryParse(rawValue);
    if (parsed == null) {
      return AudioLevelScale.defaultAlertThresholdDb;
    }
    if (AudioLevelScale.isLegacyNormalizedAlertValue(parsed)) {
      return AudioLevelScale.legacyNormalizedAlertValueToDb(parsed);
    }
    return AudioLevelScale.clampDb(parsed);
  }

  Future<void> save(AppSettings settings) async {
    await Future.wait([
      _storage.write(key: _keyServerUrl, value: settings.serverUrl ?? ''),
      _storage.write(
        key: _keyOnboardingComplete,
        value: settings.onboardingComplete.toString(),
      ),
      _storage.write(
        key: _keyVibration,
        value: settings.vibrationEnabled.toString(),
      ),
      _storage.write(
        key: _keyAlertVolume,
        value: settings.alertVolume.toString(),
      ),
      _storage.write(
        key: _keyKeepScreenOn,
        value: settings.keepScreenOn.toString(),
      ),
      _storage.write(
        key: _keyHasSeenKeepScreenOnTip,
        value: settings.hasSeenKeepScreenOnTip.toString(),
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

  Future<Set<int>> loadActiveListeningRoomIds() async {
    final raw = await _storage.read(key: _keyActiveListeningRoomIds);
    if (raw != null && raw.trim().isNotEmpty) {
      return raw
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toSet();
    }

    // Migration from older single-room key.
    final legacyRaw = await _storage.read(key: _keyActiveListeningRoomId);
    if (legacyRaw == null || legacyRaw.trim().isEmpty) {
      return {};
    }
    final legacyId = int.tryParse(legacyRaw.trim());
    if (legacyId == null) {
      return {};
    }
    final migrated = <int>{legacyId};
    await saveActiveListeningRoomIds(migrated);
    await _storage.delete(key: _keyActiveListeningRoomId);
    return migrated;
  }

  Future<void> saveApiKey(String key) async {
    final prefix = key.length >= 8 ? key.substring(0, 8) : key;
    await Future.wait([
      _storage.write(key: _keyApiKey, value: key),
      _storage.write(key: _keyApiKeyPrefix, value: prefix),
    ]);
  }

  Future<void> clearApiKey() async {
    await Future.wait([
      _storage.delete(key: _keyApiKey),
      _storage.delete(key: _keyApiKeyPrefix),
    ]);
  }

  Future<void> saveActiveListeningRoomIds(Set<int> roomIds) async {
    if (roomIds.isEmpty) {
      await _storage.delete(key: _keyActiveListeningRoomIds);
      await _storage.delete(key: _keyActiveListeningRoomId);
      return;
    }

    await _storage.write(
      key: _keyActiveListeningRoomIds,
      value: roomIds.join(','),
    );
    await _storage.delete(key: _keyActiveListeningRoomId);
  }
}
