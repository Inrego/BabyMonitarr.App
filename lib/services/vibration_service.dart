import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

class VibrationService {
  bool _hasVibrator = false;
  bool enabled = true;

  Future<void> initialize() async {
    if (kIsWeb) {
      _hasVibrator = false;
      return;
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _hasVibrator = false;
      return;
    }
    _hasVibrator = await Vibration.hasVibrator();
  }

  Future<void> vibrateAlert() async {
    if (!enabled || !_hasVibrator) return;
    await Vibration.vibrate(duration: 500, amplitude: 128);
  }

  Future<void> vibratePattern() async {
    if (!enabled || !_hasVibrator) return;
    await Vibration.vibrate(
      pattern: [0, 200, 100, 200, 100, 400],
      intensities: [0, 128, 0, 128, 0, 255],
    );
  }
}
