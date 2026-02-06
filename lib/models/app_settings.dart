class AppSettings {
  final String? serverUrl;
  final bool onboardingComplete;
  final bool darkModeEnabled;
  final String selectedTheme;
  final bool vibrationEnabled;
  final double alertVolume;

  const AppSettings({
    this.serverUrl,
    this.onboardingComplete = false,
    this.darkModeEnabled = true,
    this.selectedTheme = 'warm',
    this.vibrationEnabled = true,
    this.alertVolume = 0.5,
  });

  AppSettings copyWith({
    String? serverUrl,
    bool? onboardingComplete,
    bool? darkModeEnabled,
    String? selectedTheme,
    bool? vibrationEnabled,
    double? alertVolume,
  }) {
    return AppSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      darkModeEnabled: darkModeEnabled ?? this.darkModeEnabled,
      selectedTheme: selectedTheme ?? this.selectedTheme,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      alertVolume: alertVolume ?? this.alertVolume,
    );
  }
}
