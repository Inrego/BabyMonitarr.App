import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/audio_state.dart';

class AudioProvider extends ChangeNotifier {
  static const Duration _historyDuration = Duration(minutes: 5);
  static const int _maxHistorySize = 600;
  static const Duration _alertAutoClearDuration = Duration(seconds: 10);
  static const int _historyIntervalMs = 500;

  final Map<int, AudioSnapshot> _snapshots = <int, AudioSnapshot>{};
  final Map<int, Timer> _alertClearTimers = <int, Timer>{};
  final Map<int, int> _lastHistoryTimestamp = <int, int>{};
  final Map<int, AudioLevel?> _pendingPeak = <int, AudioLevel?>{};

  AudioSnapshot snapshotForRoom(int roomId) {
    return _snapshots[roomId] ?? const AudioSnapshot();
  }

  // Backward-compatible aggregate getters for legacy single-room widgets.
  AudioSnapshot get snapshot =>
      _snapshots.isNotEmpty ? _snapshots.values.first : const AudioSnapshot();
  AudioLevel? get currentLevel => snapshot.currentLevel;
  AlertState get alertState => snapshot.alertState;
  SoundAlert? get lastAlert => snapshot.lastAlert;
  List<AudioLevel> get history => snapshot.history;
  double get displayLevel => snapshot.currentLevel?.displayLevel ?? 0;

  SoundStatus get soundStatus {
    if (snapshot.alertState == AlertState.alerting) {
      return SoundStatus.alert;
    }
    return snapshot.currentLevel?.status ?? SoundStatus.quiet;
  }

  void onAudioLevelForRoom(int roomId, AudioLevel level) {
    final previous = _snapshots[roomId] ?? const AudioSnapshot();

    final previousPeak = _pendingPeak[roomId];
    if (previousPeak == null ||
        level.displayLevel > previousPeak.displayLevel) {
      _pendingPeak[roomId] = level;
    }

    List<AudioLevel>? updatedHistory;
    final lastHistoryAt = _lastHistoryTimestamp[roomId] ?? 0;
    if (level.timestamp - lastHistoryAt >= _historyIntervalMs) {
      final cutoff =
          DateTime.now().millisecondsSinceEpoch -
          _historyDuration.inMilliseconds;
      updatedHistory = [
        ...previous.history.where((e) => e.timestamp >= cutoff),
        _pendingPeak[roomId]!,
      ];
      if (updatedHistory.length > _maxHistorySize) {
        updatedHistory.removeRange(0, updatedHistory.length - _maxHistorySize);
      }
      _lastHistoryTimestamp[roomId] = level.timestamp;
      _pendingPeak[roomId] = null;
    }

    _snapshots[roomId] = previous.copyWith(
      currentLevel: level,
      history: updatedHistory ?? previous.history,
    );
    notifyListeners();
  }

  void onSoundAlertForRoom(int roomId, SoundAlert alert) {
    _alertClearTimers.remove(roomId)?.cancel();

    final previous = _snapshots[roomId] ?? const AudioSnapshot();
    _snapshots[roomId] = previous.copyWith(
      alertState: AlertState.alerting,
      lastAlert: alert,
    );
    notifyListeners();

    _alertClearTimers[roomId] = Timer(_alertAutoClearDuration, () {
      final current = _snapshots[roomId];
      if (current == null) return;
      _snapshots[roomId] = current.copyWith(alertState: AlertState.watching);
      notifyListeners();
    });
  }

  // Backward-compatible methods used in existing call sites/tests.
  void onAudioLevel(AudioLevel level) => onAudioLevelForRoom(0, level);
  void onSoundAlert(SoundAlert alert) => onSoundAlertForRoom(0, alert);

  void resetRoom(int roomId) {
    _alertClearTimers.remove(roomId)?.cancel();
    _lastHistoryTimestamp.remove(roomId);
    _pendingPeak.remove(roomId);
    _snapshots.remove(roomId);
    notifyListeners();
  }

  void resetAll() {
    for (final timer in _alertClearTimers.values) {
      timer.cancel();
    }
    _alertClearTimers.clear();
    _lastHistoryTimestamp.clear();
    _pendingPeak.clear();
    _snapshots.clear();
    notifyListeners();
  }

  void reset() {
    resetAll();
  }

  @override
  void dispose() {
    for (final timer in _alertClearTimers.values) {
      timer.cancel();
    }
    _alertClearTimers.clear();
    super.dispose();
  }
}
