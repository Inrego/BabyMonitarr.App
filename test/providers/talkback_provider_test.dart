import 'dart:async';

import 'package:babymonitarr/models/remote_ice_candidate.dart';
import 'package:babymonitarr/models/talkback_status.dart';
import 'package:babymonitarr/providers/talkback_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:signalr_netcore/signalr_client.dart';

import 'talkback_fakes.dart';

void main() {
  late FakeTalkbackHub hub;
  late FakeAudioControl audio;
  late List<FakeUplink> uplinks;
  late bool micGranted;
  late TalkbackProvider provider;

  setUp(() {
    hub = FakeTalkbackHub()..statuses[3] = availableStatus(3);
    audio = FakeAudioControl();
    uplinks = <FakeUplink>[];
    micGranted = true;
    provider = TalkbackProvider(
      uplinkFactory: () {
        final uplink = FakeUplink();
        uplinks.add(uplink);
        return uplink;
      },
      requestMicPermission: () async => micGranted,
    )..attach(hub: hub, audio: audio);
  });

  tearDown(() {
    provider.dispose();
    hub.dispose();
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('loadStatus stores the room status', () async {
    await provider.loadStatus(3);

    expect(provider.statusFor(3)?.available, isTrue);
    expect(provider.canTalk(3), isTrue);
  });

  test('press negotiates uplink and starts talking, mutes room', () async {
    await provider.loadStatus(3);

    await provider.startTalking(3);

    expect(provider.phaseFor(3), TalkPhase.talking);
    expect(audio.calls, ['begin(3)']);
    expect(hub.calls, contains('StartTalkbackUplink(3)'));
    expect(
      hub.calls,
      contains('SetTalkbackRemoteDescription(3,answer,answer-sdp)'),
    );
    expect(hub.calls, contains('StartTalkback(3)'));
    expect(provider.errorFor(3), isNull);
  });

  test('release stops talking, then the uplink, then restores audio', () async {
    await provider.loadStatus(3);
    await provider.startTalking(3);
    hub.calls.clear();

    await provider.stopTalking(3);

    expect(provider.phaseFor(3), TalkPhase.idle);
    expect(hub.calls, ['StopTalkback(3)', 'StopTalkbackUplink(3)']);
    expect(uplinks.single.closed, isTrue);
    expect(audio.calls, ['begin(3)', 'end(3)']);
  });

  test('shows connecting while StartTalkback is pending', () async {
    await provider.loadStatus(3);
    hub.startCompleter = Completer<TalkbackStartResult>();

    final press = provider.startTalking(3);
    await flush();
    expect(provider.phaseFor(3), TalkPhase.connecting);

    hub.startCompleter!.complete(const TalkbackStartResult(success: true));
    await press;
    expect(provider.phaseFor(3), TalkPhase.talking);
  });

  test('release during connecting stops at once and after success', () async {
    await provider.loadStatus(3);
    hub.startCompleter = Completer<TalkbackStartResult>();

    final press = provider.startTalking(3);
    await flush();
    await provider.stopTalking(3);
    await flush();
    expect(hub.calls.where((c) => c == 'StopTalkback(3)'), hasLength(1));

    hub.startCompleter!.complete(const TalkbackStartResult(success: true));
    await press;

    expect(provider.phaseFor(3), TalkPhase.idle);
    expect(hub.calls.where((c) => c == 'StopTalkback(3)'), hasLength(2));
    expect(hub.calls.last, 'StopTalkbackUplink(3)');
    expect(uplinks.single.closed, isTrue);
    expect(audio.calls.last, 'end(3)');
    expect(provider.errorFor(3), isNull);
  });

  test('cancelled start after release shows no error', () async {
    await provider.loadStatus(3);
    hub.startCompleter = Completer<TalkbackStartResult>();

    final press = provider.startTalking(3);
    await flush();
    await provider.stopTalking(3);
    hub.startCompleter!.complete(
      const TalkbackStartResult(success: false, reason: 'cancelled'),
    );
    await press;

    expect(provider.phaseFor(3), TalkPhase.idle);
    expect(provider.errorFor(3), isNull);
    expect(uplinks.single.closed, isTrue);
  });

  test('busy rejection surfaces the server message and cleans up', () async {
    await provider.loadStatus(3);
    hub.startResult = const TalkbackStartResult(
      success: false,
      reason: 'busy',
      message: 'Someone else is talking in this room',
    );

    await provider.startTalking(3);

    expect(provider.phaseFor(3), TalkPhase.idle);
    expect(provider.errorFor(3)?.kind, TalkErrorKind.rejected);
    expect(
      provider.errorFor(3)?.message,
      'Someone else is talking in this room',
    );
    expect(hub.calls, isNot(contains('StopTalkback(3)')));
    expect(hub.calls.last, 'StopTalkbackUplink(3)');
    expect(uplinks.single.closed, isTrue);
    expect(audio.calls, ['begin(3)', 'end(3)']);
  });

  test('a thrown StartTalkback is treated as a camera error', () async {
    await provider.loadStatus(3);
    hub.startError = Exception('timeout');

    await provider.startTalking(3);

    expect(provider.phaseFor(3), TalkPhase.idle);
    expect(
      provider.errorFor(3)?.message,
      TalkbackReason.describe(TalkbackReason.cameraError),
    );
  });

  test('denied mic permission never touches the server', () async {
    await provider.loadStatus(3);
    micGranted = false;

    await provider.startTalking(3);

    expect(provider.phaseFor(3), TalkPhase.idle);
    expect(provider.errorFor(3)?.kind, TalkErrorKind.micPermissionDenied);
    expect(hub.calls, ['GetTalkbackStatus(3)']);
    expect(audio.calls, isEmpty);
  });

  test('mic capture failure stops the live speaker', () async {
    await provider.loadStatus(3);
    provider.dispose();
    provider = TalkbackProvider(
      uplinkFactory: () {
        final uplink = FakeUplink()..micFails = true;
        uplinks.add(uplink);
        return uplink;
      },
      requestMicPermission: () async => true,
    )..attach(hub: hub, audio: audio);
    await provider.loadStatus(3);

    await provider.startTalking(3);

    expect(provider.phaseFor(3), TalkPhase.idle);
    expect(provider.errorFor(3)?.kind, TalkErrorKind.micPermissionDenied);
    expect(hub.calls, contains('StopTalkback(3)'));
    expect(uplinks.last.closed, isTrue);
  });

  test('uplink failure stops the live speaker', () async {
    await provider.loadStatus(3);
    hub.uplinkError = Exception('no offer');

    await provider.startTalking(3);

    expect(provider.phaseFor(3), TalkPhase.idle);
    expect(provider.errorFor(3)?.kind, TalkErrorKind.failed);
    expect(hub.calls, contains('StopTalkback(3)'));
  });

  test('cannot talk when unavailable or busy elsewhere', () async {
    hub.statuses[3] = const TalkbackStatus(
      roomId: 3,
      supported: true,
      available: false,
      unavailableReason: 'credential_failing',
    );
    await provider.loadStatus(3);
    expect(provider.canTalk(3), isFalse);

    await provider.startTalking(3);
    expect(hub.calls, isNot(contains('StartTalkback(3)')));

    hub.statusController.add(
      const TalkbackStatus(
        roomId: 3,
        supported: true,
        available: true,
        state: TalkbackState.talking,
        busy: true,
      ),
    );
    await flush();
    expect(provider.isBusyElsewhere(3), isTrue);
    expect(provider.canTalk(3), isFalse);
  });

  test('own talking is not reported as busy elsewhere', () async {
    await provider.loadStatus(3);
    await provider.startTalking(3);

    hub.statusController.add(
      const TalkbackStatus(
        roomId: 3,
        supported: true,
        available: true,
        state: TalkbackState.talking,
        busy: true,
      ),
    );
    await flush();

    expect(provider.isBusyElsewhere(3), isFalse);
    expect(provider.phaseFor(3), TalkPhase.talking);
  });

  test('server leaving talking ends the local session', () async {
    await provider.loadStatus(3);
    await provider.startTalking(3);

    hub.statusController.add(
      const TalkbackStatus(
        roomId: 3,
        supported: true,
        available: true,
        state: TalkbackState.open,
        message: 'No audio received',
      ),
    );
    await flush();
    await flush();

    expect(provider.phaseFor(3), TalkPhase.idle);
    expect(provider.errorFor(3)?.kind, TalkErrorKind.endedByServer);
    expect(uplinks.single.closed, isTrue);
    expect(audio.calls.last, 'end(3)');
  });

  test('SignalR drop ends the session without calling the server', () async {
    await provider.loadStatus(3);
    await provider.startTalking(3);
    hub.calls.clear();

    hub.connected = false;
    hub.connectionController.add(HubConnectionState.Disconnected);
    await flush();
    await flush();

    expect(provider.phaseFor(3), TalkPhase.idle);
    expect(hub.calls, isEmpty);
    expect(uplinks.single.closed, isTrue);
    expect(audio.calls.last, 'end(3)');
  });

  test('reconnect reloads known statuses', () async {
    await provider.loadStatus(3);
    hub.calls.clear();

    hub.connectionController.add(HubConnectionState.Connected);
    await flush();

    expect(hub.calls, ['GetTalkbackStatus(3)']);
  });

  test('routes ICE both ways for the talking room only', () async {
    await provider.loadStatus(3);
    await provider.startTalking(3);

    uplinks.single.onIceCandidate!(
      RTCIceCandidate('candidate:1 1 udp 1 10.0.0.2 5000 typ host', '0', 0),
    );
    hub.iceController
      ..add(
        const RemoteIceCandidate(
          roomId: 3,
          candidate: 'candidate:2',
          sdpMid: '0',
          sdpMLineIndex: 0,
        ),
      )
      ..add(
        const RemoteIceCandidate(
          roomId: 4,
          candidate: 'candidate:other',
          sdpMid: '0',
          sdpMLineIndex: 0,
        ),
      );
    await flush();

    expect(hub.localCandidates, hasLength(1));
    expect(uplinks.single.remoteCandidates, ['candidate:2']);
  });

  test('volume is debounced and shown while pending', () async {
    await provider.loadStatus(3);

    provider.setVolume(3, 1.2);
    provider.setVolume(3, 1.6);
    provider.setVolume(3, 5);
    expect(provider.volumeFor(3), 2.0);
    expect(hub.volumes, isEmpty);

    await Future<void>.delayed(
      TalkbackProvider.volumeDebounce + const Duration(milliseconds: 50),
    );

    expect(hub.volumes, [2.0]);
    expect(provider.volumeFor(3), 2.0);
    expect(provider.statusFor(3)?.volume, 2.0);
  });
}
