class AudioLevelScale {
  static const double minDb = -90.0;
  static const double maxDb = 0.0;
  static const double defaultAlertThresholdDb = -20.0;

  static const double _legacySliderMinDb = -30.0;
  static const double _legacySliderMaxDb = 0.0;

  static double clampDb(double value) => value.clamp(minDb, maxDb).toDouble();

  static double normalizeDb(double value) =>
      (clampDb(value) - minDb) / (maxDb - minDb);

  static bool isLegacyNormalizedAlertValue(double value) =>
      value >= 0.0 && value <= 1.0;

  static double legacyNormalizedAlertValueToDb(double value) {
    final normalized = value.clamp(0.0, 1.0).toDouble();
    return normalized * (_legacySliderMaxDb - _legacySliderMinDb) +
        _legacySliderMinDb;
  }
}
