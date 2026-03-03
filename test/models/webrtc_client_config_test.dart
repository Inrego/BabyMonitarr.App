import 'package:babymonitarr/models/webrtc_client_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebRtcClientConfig.fromJson', () {
    test('parses configured ICE servers', () {
      final config = WebRtcClientConfig.fromJson({
        'iceServers': [
          {'urls': 'stun:stun1.example.com:3478'},
          {
            'urls': 'turn:turn.example.com:3478',
            'username': 'user',
            'credential': 'pass',
          },
        ],
      });

      expect(config.iceServers.length, 2);
      expect(config.iceServers.first.urls, 'stun:stun1.example.com:3478');
      expect(config.iceServers.last.username, 'user');
      expect(config.iceServers.last.credential, 'pass');
    });

    test('falls back when server payload is malformed', () {
      final config = WebRtcClientConfig.fromJson({'iceServers': 'invalid'});

      expect(config.iceServers.length, 1);
      expect(config.iceServers.first.urls, 'stun:stun.l.google.com:19302');
    });
  });
}
