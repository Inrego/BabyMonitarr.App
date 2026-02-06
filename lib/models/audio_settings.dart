class AudioSettings {
  final double soundThreshold;
  final int averageSampleCount;
  final bool filterEnabled;
  final int lowPassFrequency;
  final int highPassFrequency;
  final String? cameraStreamUrl;
  final String? cameraUsername;
  final String? cameraPassword;
  final bool useCameraAudioStream;
  final int thresholdPauseDuration;
  final double volumeAdjustmentDb;

  const AudioSettings({
    this.soundThreshold = -20.0,
    this.averageSampleCount = 10,
    this.filterEnabled = false,
    this.lowPassFrequency = 4000,
    this.highPassFrequency = 300,
    this.cameraStreamUrl,
    this.cameraUsername,
    this.cameraPassword,
    this.useCameraAudioStream = false,
    this.thresholdPauseDuration = 30,
    this.volumeAdjustmentDb = -15.0,
  });

  factory AudioSettings.fromJson(Map<String, dynamic> json) {
    return AudioSettings(
      soundThreshold: (json['soundThreshold'] as num?)?.toDouble() ?? -20.0,
      averageSampleCount: json['averageSampleCount'] as int? ?? 10,
      filterEnabled: json['filterEnabled'] as bool? ?? false,
      lowPassFrequency: json['lowPassFrequency'] as int? ?? 4000,
      highPassFrequency: json['highPassFrequency'] as int? ?? 300,
      cameraStreamUrl: json['cameraStreamUrl'] as String?,
      cameraUsername: json['cameraUsername'] as String?,
      cameraPassword: json['cameraPassword'] as String?,
      useCameraAudioStream: json['useCameraAudioStream'] as bool? ?? false,
      thresholdPauseDuration: json['thresholdPauseDuration'] as int? ?? 30,
      volumeAdjustmentDb:
          (json['volumeAdjustmentDb'] as num?)?.toDouble() ?? -15.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'soundThreshold': soundThreshold,
      'averageSampleCount': averageSampleCount,
      'filterEnabled': filterEnabled,
      'lowPassFrequency': lowPassFrequency,
      'highPassFrequency': highPassFrequency,
      'cameraStreamUrl': cameraStreamUrl,
      'cameraUsername': cameraUsername,
      'cameraPassword': cameraPassword,
      'useCameraAudioStream': useCameraAudioStream,
      'thresholdPauseDuration': thresholdPauseDuration,
      'volumeAdjustmentDb': volumeAdjustmentDb,
    };
  }

  AudioSettings copyWith({
    double? soundThreshold,
    int? averageSampleCount,
    bool? filterEnabled,
    int? lowPassFrequency,
    int? highPassFrequency,
    String? cameraStreamUrl,
    String? cameraUsername,
    String? cameraPassword,
    bool? useCameraAudioStream,
    int? thresholdPauseDuration,
    double? volumeAdjustmentDb,
  }) {
    return AudioSettings(
      soundThreshold: soundThreshold ?? this.soundThreshold,
      averageSampleCount: averageSampleCount ?? this.averageSampleCount,
      filterEnabled: filterEnabled ?? this.filterEnabled,
      lowPassFrequency: lowPassFrequency ?? this.lowPassFrequency,
      highPassFrequency: highPassFrequency ?? this.highPassFrequency,
      cameraStreamUrl: cameraStreamUrl ?? this.cameraStreamUrl,
      cameraUsername: cameraUsername ?? this.cameraUsername,
      cameraPassword: cameraPassword ?? this.cameraPassword,
      useCameraAudioStream: useCameraAudioStream ?? this.useCameraAudioStream,
      thresholdPauseDuration:
          thresholdPauseDuration ?? this.thresholdPauseDuration,
      volumeAdjustmentDb: volumeAdjustmentDb ?? this.volumeAdjustmentDb,
    );
  }
}
