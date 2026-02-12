import 'package:babymonitarr/services/signalr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SignalRService.tryParseIceCandidateArgs', () {
    test('parses a valid payload with int mLine index', () {
      final parsed = SignalRService.tryParseIceCandidateArgs([
        'candidate:1 1 udp 2122260223 192.168.1.10 54321 typ host',
        '0',
        0,
      ]);

      expect(parsed, isNotNull);
      expect(parsed!.candidate, contains('candidate:1'));
      expect(parsed.sdpMid, '0');
      expect(parsed.sdpMLineIndex, 0);
    });

    test('parses numeric mLine index from num/string values', () {
      final parsedFromNum = SignalRService.tryParseIceCandidateArgs([
        'candidate:2 1 udp 2122260223 10.0.0.2 50000 typ host',
        'audio',
        1.0,
      ]);
      final parsedFromString = SignalRService.tryParseIceCandidateArgs([
        'candidate:3 1 udp 2122260223 10.0.0.3 50001 typ host',
        'audio',
        '2',
      ]);

      expect(parsedFromNum, isNotNull);
      expect(parsedFromNum!.sdpMLineIndex, 1);
      expect(parsedFromString, isNotNull);
      expect(parsedFromString!.sdpMLineIndex, 2);
    });

    test('returns null for malformed payloads', () {
      expect(SignalRService.tryParseIceCandidateArgs(null), isNull);
      expect(SignalRService.tryParseIceCandidateArgs([]), isNull);
      expect(SignalRService.tryParseIceCandidateArgs([123, '0', 0]), isNull);
      expect(SignalRService.tryParseIceCandidateArgs(['   ', '0', 0]), isNull);
    });
  });
}
