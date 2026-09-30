import 'package:babymonitarr/models/talkback_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TalkbackStatus.fromJson', () {
    test('parses a full available payload', () {
      final status = TalkbackStatus.fromJson({
        'roomId': 3,
        'supported': true,
        'available': true,
        'unavailableReason': null,
        'message': null,
        'state': 'talking',
        'busy': true,
        'volume': 1.5,
      });

      expect(status.roomId, 3);
      expect(status.supported, isTrue);
      expect(status.available, isTrue);
      expect(status.unavailableReason, isNull);
      expect(status.message, isNull);
      expect(status.state, TalkbackState.talking);
      expect(status.busy, isTrue);
      expect(status.volume, 1.5);
    });

    test('parses an unavailable payload with reason and message', () {
      final status = TalkbackStatus.fromJson({
        'roomId': '4',
        'supported': true,
        'available': false,
        'unavailableReason': 'credential_failing',
        'message': 'Sign in again',
        'state': 'closed',
        'busy': false,
        'volume': 1,
      });

      expect(status.roomId, 4);
      expect(status.available, isFalse);
      expect(status.unavailableReason, TalkbackReason.credentialFailing);
      expect(status.displayMessage, 'Sign in again');
      expect(status.volume, 1.0);
    });

    test('falls back to a reason description when message is empty', () {
      final status = TalkbackStatus.fromJson({
        'roomId': 1,
        'supported': true,
        'available': false,
        'unavailableReason': 'camera_not_mapped',
        'message': '  ',
      });

      expect(status.message, isNull);
      expect(
        status.displayMessage,
        TalkbackReason.describe(TalkbackReason.cameraNotMapped),
      );
    });

    test('defaults missing fields and clamps volume', () {
      final status = TalkbackStatus.fromJson({'roomId': 2, 'volume': 5});

      expect(status.supported, isFalse);
      expect(status.available, isFalse);
      expect(status.state, TalkbackState.closed);
      expect(status.busy, isFalse);
      expect(status.volume, 2.0);
      expect(TalkbackStatus.fromJson({'volume': -1}).volume, 0.0);
    });

    test('parses every state and treats unknown as closed', () {
      expect(TalkbackStatus.parseState('connecting'), TalkbackState.connecting);
      expect(TalkbackStatus.parseState('open'), TalkbackState.open);
      expect(TalkbackStatus.parseState('Talking'), TalkbackState.talking);
      expect(TalkbackStatus.parseState('closed'), TalkbackState.closed);
      expect(TalkbackStatus.parseState('weird'), TalkbackState.closed);
      expect(TalkbackStatus.parseState(null), TalkbackState.closed);
    });
  });

  group('TalkbackStartResult.fromJson', () {
    test('parses success', () {
      final result = TalkbackStartResult.fromJson({
        'success': true,
        'reason': null,
        'message': null,
      });

      expect(result.success, isTrue);
      expect(result.reason, isNull);
      expect(result.cancelled, isFalse);
    });

    test('parses busy failure with message', () {
      final result = TalkbackStartResult.fromJson({
        'success': false,
        'reason': 'busy',
        'message': 'Someone else is talking in this room',
      });

      expect(result.success, isFalse);
      expect(result.reason, TalkbackReason.busy);
      expect(result.displayMessage, 'Someone else is talking in this room');
    });

    test('recognises cancelled', () {
      final result = TalkbackStartResult.fromJson({
        'success': false,
        'reason': 'cancelled',
      });

      expect(result.cancelled, isTrue);
    });

    test('treats a missing success flag as failure', () {
      final result = TalkbackStartResult.fromJson({'reason': 'camera_error'});

      expect(result.success, isFalse);
      expect(
        result.displayMessage,
        TalkbackReason.describe(TalkbackReason.cameraError),
      );
    });
  });
}
