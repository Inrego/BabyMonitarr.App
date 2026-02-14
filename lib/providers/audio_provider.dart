import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/audio_state.dart';

class AudioProvider extends ChangeNotifier {
  static const Duration _historyDuration = Duration(minutes: 5);
  static const int _maxHistorySize = 600;
  static const Duration _alertAutoClearDuration = Duration(seconds: 10);
  static const int _historyIntervalMs = 500;

  AudioSnapshot _snapshot = const AudioSnapshot();
  Timer? _alertClearTimer;
  int _lastHistoryTimestamp = 0;
  AudioLevel? _pendingPeak;

  AudioSnapshot get snapshot => _snapshot;
  AudioLevel? get currentLevel => _snapshot.currentLevel;
  AlertState get alertState => _snapshot.alertState;
  SoundAlert? get lastAlert => _snapshot.lastAlert;
  List<AudioLevel> get history => _snapshot.history;

  double get displayLevel => _snapshot.currentLevel?.displayLevel ?? 0;

  SoundStatus get soundStatus {
    if (_snapshot.alertState == AlertState.alerting) {
      return SoundStatus.alert;
    }
    return _snapshot.currentLevel?.status ?? SoundStatus.quiet;
  }

  void onAudioLevel(AudioLevel level) {
    // Track the loudest sample in the current window.
    if (_pendingPeak == null ||
        level.displayLevel > _pendingPeak!.displayLevel) {
      _pendingPeak = level;
    }

    // Only append to history every _historyIntervalMs to avoid filling the
    // buffer in ~30 s when samples arrive at ~20/s.
    List<AudioLevel>? updatedHistory;
    if (level.timestamp - _lastHistoryTimestamp >= _historyIntervalMs) {
      final cutoff =
          DateTime.now().millisecondsSinceEpoch -
          _historyDuration.inMilliseconds;
      updatedHistory = [
        ..._snapshot.history.where((e) => e.timestamp >= cutoff),
        _pendingPeak!,
      ];
      if (updatedHistory.length > _maxHistorySize) {
        updatedHistory.removeRange(0, updatedHistory.length - _maxHistorySize);
      }
      _lastHistoryTimestamp = level.timestamp;
      _pendingPeak = null;
    }

    _snapshot = _snapshot.copyWith(
      currentLevel: level,
      history: updatedHistory ?? _snapshot.history,
    );
    notifyListeners();
  }

  void onSoundAlert(SoundAlert alert) {
    _alertClearTimer?.cancel();
    _snapshot = _snapshot.copyWith(
      alertState: AlertState.alerting,
      lastAlert: alert,
    );
    notifyListeners();

    _alertClearTimer = Timer(_alertAutoClearDuration, () {
      _snapshot = _snapshot.copyWith(alertState: AlertState.watching);
      notifyListeners();
    });
  }

  void reset() {
    _alertClearTimer?.cancel();
    _lastHistoryTimestamp = 0;
    _pendingPeak = null;
    _snapshot = const AudioSnapshot();
    notifyListeners();
  }

  @override
  void dispose() {
    _alertClearTimer?.cancel();
    super.dispose();
  }
}
