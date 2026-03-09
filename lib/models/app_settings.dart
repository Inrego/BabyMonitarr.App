import '../utils/audio_level_scale.dart';

class AppSettings {
  final String? serverUrl;
  final String? apiKey;
  final String? apiKeyPrefix;
  final bool onboardingComplete;
  final bool vibrationEnabled;
  final double alertVolume;
  final bool keepScreenOn;
  final bool hasSeenKeepScreenOnTip;

  const AppSettings({
    this.serverUrl,
    this.apiKey,
    this.apiKeyPrefix,
    this.onboardingComplete = false,
    this.vibrationEnabled = true,
    this.alertVolume = AudioLevelScale.defaultAlertThresholdDb,
    this.keepScreenOn = false,
    this.hasSeenKeepScreenOnTip = false,
  });

  AppSettings copyWith({
    String? serverUrl,
    String? apiKey,
    String? apiKeyPrefix,
    bool? onboardingComplete,
    bool? vibrationEnabled,
    double? alertVolume,
    bool? keepScreenOn,
    bool? hasSeenKeepScreenOnTip,
  }) {
    return AppSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      apiKey: apiKey ?? this.apiKey,
      apiKeyPrefix: apiKeyPrefix ?? this.apiKeyPrefix,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      alertVolume: alertVolume ?? this.alertVolume,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      hasSeenKeepScreenOnTip:
          hasSeenKeepScreenOnTip ?? this.hasSeenKeepScreenOnTip,
    );
  }
}
