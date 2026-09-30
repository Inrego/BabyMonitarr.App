import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';
import '../models/webrtc_client_config.dart';
import 'webrtc_service.dart';

final _log = Logger('TalkbackUplinkService');

/// Thrown when the platform refuses microphone capture.
class MicrophoneUnavailableException implements Exception {
  final Object? cause;
  const MicrophoneUnavailableException([this.cause]);

  @override
  String toString() => 'MicrophoneUnavailableException: $cause';
}

/// One talkback uplink: the phone's microphone sent to the backend over its
/// own peer connection. Abstract so the provider can be tested without a
/// platform WebRTC stack.
abstract class TalkbackUplink {
  /// Applies the server's recvonly offer, captures the mic and returns the
  /// answer SDP (audio `sendonly`).
  Future<String> handleOffer(
    String sdpOffer, {
    required void Function(RTCIceCandidate candidate) onIceCandidate,
    WebRtcClientConfig? clientConfig,
  });

  Future<void> addRemoteCandidate(
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  );

  /// Stops the mic track and closes the peer connection. Idempotent.
  Future<void> close();
}

/// Mic uplink on a dedicated [RTCPeerConnection]. Deliberately separate from
/// [WebRtcService]: the monitoring peer connections are never touched.
class TalkbackUplinkService implements TalkbackUplink {
  static const Map<String, dynamic> micConstraints = {
    'audio': {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    },
    'video': false,
  };

  RTCPeerConnection? _peerConnection;
  MediaStream? _micStream;
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;
  bool _closed = false;

  @override
  Future<String> handleOffer(
    String sdpOffer, {
    required void Function(RTCIceCandidate candidate) onIceCandidate,
    WebRtcClientConfig? clientConfig,
  }) async {
    final config = (clientConfig ?? WebRtcClientConfig.fallback())
        .toPeerConnectionConfig();
    final pc = await createPeerConnection(config);
    if (_closed) {
      await _disposePeerConnection(pc);
      throw StateError('Talkback uplink closed during setup');
    }
    _peerConnection = pc;

    pc.onConnectionState = (state) {
      _log.info('Uplink PeerConnection state: ${state.name}');
    };
    pc.onIceCandidate = onIceCandidate;

    await pc.setRemoteDescription(RTCSessionDescription(sdpOffer, 'offer'));
    _remoteDescriptionSet = true;
    for (final candidate in _pendingCandidates) {
      await _addCandidateSafely(pc, candidate);
    }
    _pendingCandidates.clear();

    final MediaStream stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia(micConstraints);
    } catch (e, st) {
      _log.warning('Microphone capture failed', e, st);
      throw MicrophoneUnavailableException(e);
    }
    if (_closed) {
      await _stopStream(stream);
      throw StateError('Talkback uplink closed during setup');
    }
    _micStream = stream;

    // addTrack reuses the recvonly transceiver created by the offer, so the
    // answer's single audio section becomes sendonly.
    for (final track in stream.getAudioTracks()) {
      await pc.addTrack(track, stream);
    }

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _log.info('Uplink answer created');
    return answer.sdp!;
  }

  @override
  Future<void> addRemoteCandidate(
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) async {
    if (_closed) return;
    final normalized = candidate.startsWith('candidate:')
        ? candidate
        : 'candidate:$candidate';
    if (WebRtcService.isLoopbackIceCandidate(normalized)) return;

    final iceCandidate = RTCIceCandidate(normalized, sdpMid, sdpMLineIndex);
    final pc = _peerConnection;
    if (_remoteDescriptionSet && pc != null) {
      await _addCandidateSafely(pc, iceCandidate);
    } else {
      _pendingCandidates.add(iceCandidate);
    }
  }

  Future<void> _addCandidateSafely(
    RTCPeerConnection pc,
    RTCIceCandidate candidate,
  ) async {
    try {
      await pc.addCandidate(candidate);
    } catch (e, st) {
      _log.warning('Failed to add uplink ICE candidate', e, st);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pendingCandidates.clear();

    final stream = _micStream;
    _micStream = null;
    if (stream != null) await _stopStream(stream);

    final pc = _peerConnection;
    _peerConnection = null;
    if (pc != null) await _disposePeerConnection(pc);
  }

  Future<void> _stopStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      try {
        await track.stop();
      } catch (e, st) {
        _log.warning('Error stopping mic track', e, st);
      }
    }
    try {
      await stream.dispose();
    } catch (e, st) {
      _log.warning('Error disposing mic stream', e, st);
    }
  }

  Future<void> _disposePeerConnection(RTCPeerConnection pc) async {
    pc.onConnectionState = null;
    pc.onIceCandidate = null;
    try {
      await pc.close();
      await pc.dispose();
    } catch (e, st) {
      _log.warning('Error closing uplink peer connection', e, st);
    }
  }
}
