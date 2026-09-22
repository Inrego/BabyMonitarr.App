import 'package:babymonitarr/models/cast_device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CastDevice.fromJson', () {
    test('parses a discovered display that is casting a room', () {
      final device = CastDevice.fromJson({
        'deviceId': 'abc123',
        'name': 'Living Room TV',
        'model': 'Chromecast Ultra',
        'host': '192.168.0.42',
        'isVideoCapable': true,
        'isGroup': false,
        'manuallyAdded': false,
        'isOnline': true,
        'lastSeenUtc': '2026-09-22T20:10:00Z',
        'castingRoomId': 3,
      });

      expect(device.name, 'Living Room TV');
      expect(device.isVideoCapable, isTrue);
      expect(device.isCasting, isTrue);
      expect(device.castingRoomId, 3);
      expect(device.lastSeenUtc, DateTime.utc(2026, 9, 22, 20, 10));
    });

    test('falls back to defaults on a sparse payload', () {
      final device = CastDevice.fromJson({'deviceId': 'speaker-1'});

      expect(device.deviceId, 'speaker-1');
      expect(device.name, isEmpty);
      expect(device.isVideoCapable, isFalse);
      expect(device.isOnline, isFalse);
      expect(device.isCasting, isFalse);
      expect(device.lastSeenUtc, isNull);
    });

    test('ignores a malformed lastSeenUtc instead of throwing', () {
      final device = CastDevice.fromJson({
        'deviceId': 'speaker-1',
        'lastSeenUtc': 'not-a-date',
      });

      expect(device.lastSeenUtc, isNull);
    });
  });

  group('CastStartResult.fromJson', () {
    test('parses started sessions and per-device failures', () {
      final result = CastStartResult.fromJson({
        'started': [
          {
            'deviceId': 'abc123',
            'roomId': 3,
            'video': true,
            'startedAtUtc': '2026-09-22T20:11:00Z',
          },
        ],
        'failed': {'speaker-1': 'Could not reach the device.'},
      });

      expect(result.started.single.deviceId, 'abc123');
      expect(result.started.single.video, isTrue);
      expect(result.hasFailures, isTrue);
      expect(result.failed['speaker-1'], 'Could not reach the device.');
    });

    test('treats a malformed payload as an empty result', () {
      final result = CastStartResult.fromJson({
        'started': 'nope',
        'failed': 42,
      });

      expect(result.started, isEmpty);
      expect(result.hasFailures, isFalse);
    });
  });
}
