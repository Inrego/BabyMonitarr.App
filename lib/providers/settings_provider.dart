import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';
import '../models/audio_settings.dart';
import '../services/settings_service.dart';

class SettingsProvider extends ChangeNotifier {
  final SettingsService _service;
  AppSettings _settings = const AppSettings();
  AudioSettings _audioSettings = const AudioSettings();
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

  Future<void> _loadSettings() async {
    _settings = await _service.load();
    _isLoading = false;
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
}
