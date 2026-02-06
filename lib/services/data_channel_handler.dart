import 'dart:convert';
import 'dart:async';
import '../models/audio_state.dart';

class DataChannelHandler {
  final _audioLevelController = StreamController<AudioLevel>.broadcast();
  final _soundAlertController = StreamController<SoundAlert>.broadcast();

  Stream<AudioLevel> get audioLevels => _audioLevelController.stream;
  Stream<SoundAlert> get soundAlerts => _soundAlertController.stream;

  void handleMessage(String message) {
    try {
      final json = jsonDecode(message) as Map<String, dynamic>;
      final type = json['type'] as String?;

      switch (type) {
        case 'audioLevel':
          _audioLevelController.add(AudioLevel.fromJson(json));
          break;
        case 'soundAlert':
          _soundAlertController.add(SoundAlert.fromJson(json));
          break;
      }
    } catch (e) {
      // Silently ignore malformed messages
    }
  }

  void dispose() {
    _audioLevelController.close();
    _soundAlertController.close();
  }
}
