import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/app_settings.dart';
import '../models/audio_settings.dart';
import '../services/settings_service.dart';

class SettingsProvider extends ChangeNotifier {
  final SettingsService _service;
  AppSettings _settings = const AppSettings();
  AudioSettings _audioSettings = const AudioSettings();
  Set<int> _monitoringRoomIds = {};
  Set<int> _activeListeningRoomIds = {};
  bool _isLoading = true;

  SettingsProvider({SettingsService? service})
    : _service = service ?? SettingsService() {
    _loadSettings();
  }

  AppSettings get settings => _settings;
  AudioSettings get audioSettings => _audioSettings;
  bool get isLoading => _isLoading;
  bool get isOnboardingComplete => _settings.onboardingComplete;
  String? get serverUrl => _settings.serverUrl;

  Set<int> get monitoringRoomIds => _monitoringRoomIds;
  Set<int> get activeListeningRoomIds => _activeListeningRoomIds;

  Future<void> _loadSettings() async {
    _settings = await _service.load();
    _monitoringRoomIds = await _service.loadMonitoringRoomIds();
    _activeListeningRoomIds = await _service.loadActiveListeningRoomIds();
    _isLoading = false;
    if (_settings.keepScreenOn) {
      WakelockPlus.enable();
    }
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    _settings = _settings.copyWith(serverUrl: url);
    await _service.save(_settings);
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    _settings = _settings.copyWith(onboardingComplete: true);
    await _service.save(_settings);
    notifyListeners();
  }

  Future<void> setDarkMode(bool enabled) async {
    _settings = _settings.copyWith(darkModeEnabled: enabled);
    await _service.save(_settings);
    notifyListeners();
  }

  Future<void> setTheme(String theme) async {
    _settings = _settings.copyWith(selectedTheme: theme);
    await _service.save(_settings);
    notifyListeners();
  }

  Future<void> setVibrationEnabled(bool enabled) async {
    _settings = _settings.copyWith(vibrationEnabled: enabled);
    await _service.save(_settings);
    notifyListeners();
  }

  Future<void> setAlertVolume(double volume) async {
    _settings = _settings.copyWith(alertVolume: volume);
    await _service.save(_settings);
    notifyListeners();
  }

  bool get keepScreenOn => _settings.keepScreenOn;

  Future<void> setKeepScreenOn(bool enabled) async {
    _settings = _settings.copyWith(keepScreenOn: enabled);
    await _service.save(_settings);
    if (enabled) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
    notifyListeners();
  }

  Future<void> setMonitoringRoomIds(Set<int> ids) async {
    await _updateMonitoringRoomIds(ids);
  }

  Future<void> addMonitoringRoom(int id) async {
    await _updateMonitoringRoomIds({..._monitoringRoomIds, id});
  }

  Future<void> removeMonitoringRoom(int id) async {
    await _updateMonitoringRoomIds({..._monitoringRoomIds}..remove(id));
    if (_activeListeningRoomIds.contains(id)) {
      await setActiveListeningRoomIds({..._activeListeningRoomIds}..remove(id));
    }
  }

  Future<void> setActiveListeningRoomIds(Set<int> roomIds) async {
    final next = {...roomIds};
    if (_activeListeningRoomIds.length == next.length &&
        _activeListeningRoomIds.containsAll(next)) {
      return;
    }
    final previous = {..._activeListeningRoomIds};
    _activeListeningRoomIds = next;
    notifyListeners();
    try {
      await _service.saveActiveListeningRoomIds(next);
    } catch (_) {
      _activeListeningRoomIds = previous;
      notifyListeners();
      rethrow;
    }
  }

  void updateAudioSettings(AudioSettings settings) {
    _audioSettings = settings;
    notifyListeners();
  }

  AudioSettings getUpdatedAudioSettings({
    double? volumeAdjustmentDb,
    bool? filterEnabled,
  }) {
    _audioSettings = _audioSettings.copyWith(
      volumeAdjustmentDb: volumeAdjustmentDb,
      filterEnabled: filterEnabled,
    );
    notifyListeners();
    return _audioSettings;
  }

  Future<void> _updateMonitoringRoomIds(Set<int> ids) async {
    final previous = {..._monitoringRoomIds};
    final next = {...ids};
    _monitoringRoomIds = next;
    notifyListeners();
    try {
      await _service.saveMonitoringRoomIds(next);
    } catch (_) {
      _monitoringRoomIds = previous;
      notifyListeners();
      rethrow;
    }
  }
}
