import 'package:babymonitarr/services/signalr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SignalRService.tryParseIceCandidateArgs', () {
    test('parses a valid payload with int mLine index', () {
      final parsed = SignalRService.tryParseIceCandidateArgs([
        5,
        'candidate:1 1 udp 2122260223 192.168.1.10 54321 typ host',
        '0',
        0,
      ]);

      expect(parsed, isNotNull);
      expect(parsed!.roomId, 5);
      expect(parsed.candidate, contains('candidate:1'));
      expect(parsed.sdpMid, '0');
      expect(parsed.sdpMLineIndex, 0);
    });

    test('parses numeric mLine index from num/string values', () {
      final parsedFromNum = SignalRService.tryParseIceCandidateArgs([
        6,
        'candidate:2 1 udp 2122260223 10.0.0.2 50000 typ host',
        'audio',
        1.0,
      ]);
      final parsedFromString = SignalRService.tryParseIceCandidateArgs([
        7,
        'candidate:3 1 udp 2122260223 10.0.0.3 50001 typ host',
        'audio',
        '2',
      ]);

      expect(parsedFromNum, isNotNull);
      expect(parsedFromNum!.sdpMLineIndex, 1);
      expect(parsedFromNum.roomId, 6);
      expect(parsedFromString, isNotNull);
      expect(parsedFromString!.sdpMLineIndex, 2);
      expect(parsedFromString.roomId, 7);
    });

    test('returns null for malformed payloads', () {
      expect(SignalRService.tryParseIceCandidateArgs(null), isNull);
      expect(SignalRService.tryParseIceCandidateArgs([]), isNull);
      expect(
        SignalRService.tryParseIceCandidateArgs([
          'invalid-room',
          'candidate:1 1 udp 2122260223 10.0.0.4 55555 typ host',
          '0',
          0,
        ]),
        isNull,
      );
      expect(SignalRService.tryParseIceCandidateArgs([1, 123, '0', 0]), isNull);
      expect(
        SignalRService.tryParseIceCandidateArgs([1, '   ', '0', 0]),
        isNull,
      );
    });
  });

  group('SignalRService.tryParseVideoIceCandidateArgs', () {
    test('parses a valid video ICE payload', () {
      final parsed = SignalRService.tryParseVideoIceCandidateArgs([
        7,
        'candidate:1 1 udp 2122260223 10.0.0.4 55555 typ host',
        '1',
        0,
      ]);

      expect(parsed, isNotNull);
      expect(parsed!.roomId, 7);
      expect(parsed.candidate, contains('candidate:1'));
      expect(parsed.sdpMid, '1');
      expect(parsed.sdpMLineIndex, 0);
    });

    test('returns null for malformed video ICE payloads', () {
      expect(SignalRService.tryParseVideoIceCandidateArgs(null), isNull);
      expect(SignalRService.tryParseVideoIceCandidateArgs([]), isNull);
      expect(
        SignalRService.tryParseVideoIceCandidateArgs([
          'invalid-room',
          'candidate:1 1 udp 2122260223 10.0.0.4 55555 typ host',
        ]),
        isNull,
      );
      expect(
        SignalRService.tryParseVideoIceCandidateArgs([1, '   ', '1', 0]),
        isNull,
      );
    });
  });

  group('SignalRService.normalizeServerUrl', () {
    test('normalizes trailing slash and /audioHub suffix', () {
      expect(
        SignalRService.normalizeServerUrl('http://localhost:5148/'),
        'http://localhost:5148',
      );
      expect(
        SignalRService.normalizeServerUrl('http://localhost:5148/audioHub'),
        'http://localhost:5148',
      );
    });
  });

  group('SignalRService.reconnectDelayForAttempt', () {
    test('keeps reconnecting forever with capped delay', () {
      expect(SignalRService.reconnectDelayForAttempt(0), 0);
      expect(SignalRService.reconnectDelayForAttempt(1), 2000);
      expect(SignalRService.reconnectDelayForAttempt(2), 5000);
      expect(SignalRService.reconnectDelayForAttempt(3), 10000);
      expect(SignalRService.reconnectDelayForAttempt(4), 15000);
      expect(SignalRService.reconnectDelayForAttempt(8), 15000);
      expect(SignalRService.reconnectDelayForAttempt(1000), 15000);
    });
  });
}
