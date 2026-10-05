import 'package:babymonitarr/utils/video_resume_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  const connected = RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  VideoResumeAction decide({
    bool wasBackgrounded = false,
    RTCPeerConnectionState? state = connected,
    bool isLoading = false,
    bool hasStream = true,
    bool hasError = false,
  }) => videoResumeAction(
    wasBackgrounded: wasBackgrounded,
    connectionState: state,
    isLoading: isLoading,
    hasStream: hasStream,
    hasError: hasError,
  );

  group('videoResumeAction', () {
    test('keeps a healthy session after only going inactive', () {
      expect(decide(), VideoResumeAction.keep);
    });

    test('refreshes the renderer of a healthy session after background', () {
      expect(decide(wasBackgrounded: true), VideoResumeAction.refreshRenderer);
    });

    for (final state in [
      RTCPeerConnectionState.RTCPeerConnectionStateFailed,
      RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
      RTCPeerConnectionState.RTCPeerConnectionStateClosed,
    ]) {
      test('rebuilds when peer connection is ${state.name}', () {
        expect(decide(state: state), VideoResumeAction.rebuild);
        expect(
          decide(state: state, wasBackgrounded: true),
          VideoResumeAction.rebuild,
        );
      });
    }

    test('rebuilds a session that errored', () {
      expect(decide(hasError: true), VideoResumeAction.rebuild);
    });

    test('rebuilds a connected session that never got a stream', () {
      expect(decide(hasStream: false), VideoResumeAction.rebuild);
    });

    test('leaves a session that is still negotiating alone', () {
      expect(
        decide(
          state: RTCPeerConnectionState.RTCPeerConnectionStateConnecting,
          isLoading: true,
          hasStream: false,
          wasBackgrounded: true,
        ),
        VideoResumeAction.keep,
      );
    });
  });
}
