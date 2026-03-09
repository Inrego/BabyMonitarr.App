import 'package:babymonitarr/utils/audio_level_scale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioLevelScale', () {
    test('normalizes the shared dashboard dB range', () {
      expect(AudioLevelScale.normalizeDb(AudioLevelScale.minDb), 0.0);
      expect(AudioLevelScale.normalizeDb(-45.0), 0.5);
      expect(AudioLevelScale.normalizeDb(AudioLevelScale.maxDb), 1.0);
    });

    test('converts legacy normalized slider values to dB', () {
      expect(AudioLevelScale.isLegacyNormalizedAlertValue(0.0), isTrue);
      expect(AudioLevelScale.legacyNormalizedAlertValueToDb(0.0), -30.0);
      expect(AudioLevelScale.legacyNormalizedAlertValueToDb(0.5), -15.0);
      expect(AudioLevelScale.legacyNormalizedAlertValueToDb(1.0), 0.0);
    });

    test('clamps out-of-range dB values', () {
      expect(AudioLevelScale.clampDb(-120.0), AudioLevelScale.minDb);
      expect(AudioLevelScale.clampDb(12.0), AudioLevelScale.maxDb);
    });
  });
}
