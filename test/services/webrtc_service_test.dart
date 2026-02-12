import 'package:babymonitarr/services/webrtc_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebRtcService.isLoopbackIceCandidate', () {
    test('returns true for IPv4 and IPv6 loopback candidates', () {
      expect(
        WebRtcService.isLoopbackIceCandidate(
          'candidate:1 1 udp 2122260223 127.0.0.1 54321 typ host',
        ),
        isTrue,
      );

      expect(
        WebRtcService.isLoopbackIceCandidate(
          'candidate:2 1 udp 2122260223 ::1 54321 typ host',
        ),
        isTrue,
      );
    });

    test('returns false for routable host and srflx candidates', () {
      expect(
        WebRtcService.isLoopbackIceCandidate(
          'candidate:3 1 udp 2122260223 192.168.20.253 47838 typ host',
        ),
        isFalse,
      );

      expect(
        WebRtcService.isLoopbackIceCandidate(
          'candidate:4 1 udp 1686052607 5.103.135.124 47838 typ srflx raddr 192.168.20.253 rport 47838',
        ),
        isFalse,
      );
    });
  });
}
