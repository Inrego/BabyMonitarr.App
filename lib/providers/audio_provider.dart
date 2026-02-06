import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/audio_state.dart';

class AudioProvider extends ChangeNotifier {
  static const int _maxHistorySize = 60;
  static const Duration _alertAutoClearDuration = Duration(seconds: 10);

  AudioSnapshot _snapshot = const AudioSnapshot();
  Timer? _alertClearTimer;

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
    final updatedHistory = [..._snapshot.history, level];
    if (updatedHistory.length > _maxHistorySize) {
      updatedHistory.removeRange(0, updatedHistory.length - _maxHistorySize);
    }

    _snapshot = _snapshot.copyWith(
      currentLevel: level,
      history: updatedHistory,
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
    _snapshot = const AudioSnapshot();
    notifyListeners();
  }

  @override
  void dispose() {
    _alertClearTimer?.cancel();
    super.dispose();
  }
}
