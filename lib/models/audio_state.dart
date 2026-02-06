class AudioLevel {
  final double level;
  final int timestamp;

  const AudioLevel({required this.level, required this.timestamp});

  factory AudioLevel.fromJson(Map<String, dynamic> json) {
    return AudioLevel(
      level: (json['level'] as num).toDouble(),
      timestamp: json['timestamp'] as int,
    );
  }

  double get displayLevel => level.abs();

  SoundStatus get status {
    final absLevel = level.abs();
    if (absLevel < 40) return SoundStatus.quiet;
    if (absLevel < 55) return SoundStatus.moderate;
    return SoundStatus.active;
  }
}

class SoundAlert {
  final double level;
  final double threshold;
  final int timestamp;

  const SoundAlert({
    required this.level,
    required this.threshold,
    required this.timestamp,
  });

  factory SoundAlert.fromJson(Map<String, dynamic> json) {
    return SoundAlert(
      level: (json['level'] as num).toDouble(),
      threshold: (json['threshold'] as num).toDouble(),
      timestamp: json['timestamp'] as int,
    );
  }
}

enum SoundStatus { quiet, moderate, active, alert }

enum AlertState { idle, watching, alerting }

class AudioSnapshot {
  final AudioLevel? currentLevel;
  final AlertState alertState;
  final SoundAlert? lastAlert;
  final List<AudioLevel> history;

  const AudioSnapshot({
    this.currentLevel,
    this.alertState = AlertState.watching,
    this.lastAlert,
    this.history = const [],
  });

  AudioSnapshot copyWith({
    AudioLevel? currentLevel,
    AlertState? alertState,
    SoundAlert? lastAlert,
    List<AudioLevel>? history,
  }) {
    return AudioSnapshot(
      currentLevel: currentLevel ?? this.currentLevel,
      alertState: alertState ?? this.alertState,
      lastAlert: lastAlert ?? this.lastAlert,
      history: history ?? this.history,
    );
  }
}
