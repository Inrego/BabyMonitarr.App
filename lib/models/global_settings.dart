class GlobalSettings {
  final int id;
  final double soundThreshold;
  final int averageSampleCount;
  final bool filterEnabled;
  final int lowPassFrequency;
  final int highPassFrequency;
  final int thresholdPauseDuration;
  final double volumeAdjustmentDb;

  const GlobalSettings({
    this.id = 1,
    this.soundThreshold = -20.0,
    this.averageSampleCount = 10,
    this.filterEnabled = false,
    this.lowPassFrequency = 4000,
    this.highPassFrequency = 300,
    this.thresholdPauseDuration = 30,
    this.volumeAdjustmentDb = -15.0,
  });

  factory GlobalSettings.fromJson(Map<String, dynamic> json) {
    return GlobalSettings(
      id: (json['id'] as num?)?.toInt() ?? 1,
      soundThreshold: (json['soundThreshold'] as num?)?.toDouble() ?? -20.0,
      averageSampleCount: (json['averageSampleCount'] as num?)?.toInt() ?? 10,
      filterEnabled: json['filterEnabled'] as bool? ?? false,
      lowPassFrequency: (json['lowPassFrequency'] as num?)?.toInt() ?? 4000,
      highPassFrequency: (json['highPassFrequency'] as num?)?.toInt() ?? 300,
      thresholdPauseDuration:
          (json['thresholdPauseDuration'] as num?)?.toInt() ?? 30,
      volumeAdjustmentDb:
          (json['volumeAdjustmentDb'] as num?)?.toDouble() ?? -15.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'soundThreshold': soundThreshold,
      'averageSampleCount': averageSampleCount,
      'filterEnabled': filterEnabled,
      'lowPassFrequency': lowPassFrequency,
      'highPassFrequency': highPassFrequency,
      'thresholdPauseDuration': thresholdPauseDuration,
      'volumeAdjustmentDb': volumeAdjustmentDb,
    };
  }

  GlobalSettings copyWith({
    int? id,
    double? soundThreshold,
    int? averageSampleCount,
    bool? filterEnabled,
    int? lowPassFrequency,
    int? highPassFrequency,
    int? thresholdPauseDuration,
    double? volumeAdjustmentDb,
  }) {
    return GlobalSettings(
      id: id ?? this.id,
      soundThreshold: soundThreshold ?? this.soundThreshold,
      averageSampleCount: averageSampleCount ?? this.averageSampleCount,
      filterEnabled: filterEnabled ?? this.filterEnabled,
      lowPassFrequency: lowPassFrequency ?? this.lowPassFrequency,
      highPassFrequency: highPassFrequency ?? this.highPassFrequency,
      thresholdPauseDuration:
          thresholdPauseDuration ?? this.thresholdPauseDuration,
      volumeAdjustmentDb: volumeAdjustmentDb ?? this.volumeAdjustmentDb,
    );
  }
}
