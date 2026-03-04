class AppSettings {
  final String? serverUrl;
  final String? apiKey;
  final String? apiKeyPrefix;
  final bool onboardingComplete;
  final bool darkModeEnabled;
  final String selectedTheme;
  final bool vibrationEnabled;
  final double alertVolume;
  final bool keepScreenOn;
  final bool hasSeenKeepScreenOnTip;

  const AppSettings({
    this.serverUrl,
    this.apiKey,
    this.apiKeyPrefix,
    this.onboardingComplete = false,
    this.darkModeEnabled = true,
    this.selectedTheme = 'warm',
    this.vibrationEnabled = true,
    this.alertVolume = 0.5,
    this.keepScreenOn = false,
    this.hasSeenKeepScreenOnTip = false,
  });

  AppSettings copyWith({
    String? serverUrl,
    String? apiKey,
    String? apiKeyPrefix,
    bool? onboardingComplete,
    bool? darkModeEnabled,
    String? selectedTheme,
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
      darkModeEnabled: darkModeEnabled ?? this.darkModeEnabled,
      selectedTheme: selectedTheme ?? this.selectedTheme,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      alertVolume: alertVolume ?? this.alertVolume,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      hasSeenKeepScreenOnTip: hasSeenKeepScreenOnTip ?? this.hasSeenKeepScreenOnTip,
    );
  }
}
