import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'data_channel_handler.dart';
import '../models/webrtc_client_config.dart';

class WebRtcService {
  RTCPeerConnection? _peerConnection;
  final DataChannelHandler _dataChannelHandler;
  final List<RTCIceCandidate> _pendingCandidates = [];
  final Set<String> _seenRemoteCandidateKeys = <String>{};
  // Cache remote audio tracks as they arrive via onTrack so we can mute them
  // synchronously from the stop path — `getReceivers()` is async and would race
  // with pc.close().
  final List<MediaStreamTrack> _remoteAudioTracks = [];
  bool _remoteDescriptionSet = false;
  bool _audioEnabled = true;
  Timer? _statsTimer;
  bool _closing = false;

  final _connectionStateController =
      StreamController<RTCPeerConnectionState>.broadcast();
  final _qualityController = StreamController<double>.broadcast();

  Stream<RTCPeerConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<double> get packetLossStream => _qualityController.stream;
  DataChannelHandler get dataChannelHandler => _dataChannelHandler;
  bool get audioEnabled => _audioEnabled;

  WebRtcService({DataChannelHandler? dataChannelHandler})
    : _dataChannelHandler = dataChannelHandler ?? DataChannelHandler();

  Future<String> handleOffer(
    String sdpOffer, {
    void Function(RTCIceCandidate candidate)? onIceCandidate,
    WebRtcClientConfig? clientConfig,
  }) async {
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    _seenRemoteCandidateKeys.clear();

    final config = (clientConfig ?? WebRtcClientConfig.fallback())
        .toPeerConnectionConfig();

    _peerConnection = await createPeerConnection(config);

    _peerConnection!.onConnectionState = (state) {
      _connectionStateController.add(state);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _startStatsPolling();
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _stopStatsPolling();
      }
    };

    _peerConnection!.onTrack = (event) {
      debugPrint('WebRTC: Received track: ${event.track.kind}');
      // Audio tracks auto-play through device speaker. Cache the track so we
      // can disable it synchronously from the stop path.
      if (event.track.kind == 'audio') {
        _remoteAudioTracks.add(event.track);
      }
    };

    _peerConnection!.onDataChannel = (channel) {
      debugPrint('WebRTC: Data channel opened: ${channel.label}');
      channel.onMessage = (message) {
        _dataChannelHandler.handleMessage(message.text);
      };
    };

    // Set up ICE candidate callback BEFORE setting remote description
    // so no candidates generated during createAnswer/setLocalDescription are lost
    if (onIceCandidate != null) {
      _peerConnection!.onIceCandidate = onIceCandidate;
    }

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdpOffer, 'offer'),
    );
    _remoteDescriptionSet = true;

    // Flush queued ICE candidates
    for (final candidate in _pendingCandidates) {
      await _peerConnection!.addCandidate(candidate);
    }
    _pendingCandidates.clear();

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    return answer.sdp!;
  }

  Future<void> addIceCandidate(
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) async {
    // WebRTC spec requires the 'candidate:' prefix
    final normalized = candidate.startsWith('candidate:')
        ? candidate
        : 'candidate:$candidate';

    if (isLoopbackIceCandidate(normalized)) {
      debugPrint('WebRTC: Dropping loopback ICE candidate: $normalized');
      return;
    }

    final candidateKey = _buildCandidateKey(normalized, sdpMid, sdpMLineIndex);
    if (!_seenRemoteCandidateKeys.add(candidateKey)) {
      debugPrint('WebRTC: Dropping duplicate ICE candidate');
      return;
    }

    final iceCandidate = RTCIceCandidate(normalized, sdpMid, sdpMLineIndex);

    try {
      if (_remoteDescriptionSet && _peerConnection != null) {
        await _peerConnection!.addCandidate(iceCandidate);
      } else {
        _pendingCandidates.add(iceCandidate);
      }
    } catch (e) {
      debugPrint('WebRTC: Failed to add ICE candidate: $e');
    }
  }

  void toggleAudio() {
    _audioEnabled = !_audioEnabled;
    _setAudioEnabled(_audioEnabled);
  }

  void setAudioEnabled(bool enabled) {
    _audioEnabled = enabled;
    // Apply synchronously to cached remote tracks so playback flips immediately
    // without waiting for `getReceivers()` to resolve. Also run the async path
    // as a belt-and-braces fallback in case onTrack didn't fire (e.g. audio
    // track arrived via a receiver without a track event).
    _applyAudioEnabledSync(enabled);
    _setAudioEnabled(enabled);
  }

  /// Synchronous mute/unmute on the cached remote audio tracks. Safe to call
  /// from a stop path that must not await before flipping audio state.
  void _applyAudioEnabledSync(bool enabled) {
    for (final track in _remoteAudioTracks) {
      try {
        track.enabled = enabled;
      } catch (e) {
        debugPrint('Error toggling remote audio track: $e');
      }
    }
  }

  Future<void> _setAudioEnabled(bool enabled) async {
    if (_peerConnection == null) return;
    try {
      final receivers = await _peerConnection!.getReceivers();
      for (final receiver in receivers.where(
        (r) => r.track != null && r.track!.kind == 'audio',
      )) {
        receiver.track!.enabled = enabled;
      }
    } catch (e) {
      debugPrint('Error setting audio enabled: $e');
    }
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _pollStats();
    });
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  Future<void> _pollStats() async {
    if (_peerConnection == null) return;
    try {
      final stats = await _peerConnection!.getStats();
      for (final report in stats) {
        if (report.type == 'inbound-rtp') {
          final packetsReceived =
              (report.values['packetsReceived'] as num?)?.toDouble() ?? 0;
          final packetsLost =
              (report.values['packetsLost'] as num?)?.toDouble() ?? 0;
          final total = packetsReceived + packetsLost;
          if (total > 0) {
            final lossPercent = (packetsLost / total) * 100;
            _qualityController.add(lossPercent);
          }
        }
      }
    } catch (e) {
      // Stats polling failure is non-critical
    }
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;

    _stopStatsPolling();
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    _seenRemoteCandidateKeys.clear();
    _remoteAudioTracks.clear();

    final pc = _peerConnection;
    _peerConnection = null;

    if (pc == null) {
      _closing = false;
      return;
    }

    try {
      pc.onConnectionState = null;
      pc.onTrack = null;
      pc.onDataChannel = null;
      pc.onIceCandidate = null;
    } catch (e) {
      debugPrint('Error clearing peer connection callbacks: $e');
    }

    try {
      await pc.close();
    } catch (e) {
      debugPrint('Error closing peer connection: $e');
    }

    try {
      await pc.dispose();
    } catch (e) {
      debugPrint('Error disposing peer connection: $e');
    }

    _closing = false;
  }

  static bool isLoopbackIceCandidate(String candidate) {
    final tokens = candidate.split(RegExp(r'\s+'));
    if (tokens.length >= 5) {
      final address = tokens[4].toLowerCase();
      if (address == '127.0.0.1' ||
          address == '::1' ||
          address == 'localhost') {
        return true;
      }
    }

    final normalized = candidate.toLowerCase();
    return normalized.contains(' 127.0.0.1 ') ||
        normalized.contains(' ::1 ') ||
        normalized.contains(' localhost ');
  }

  String _buildCandidateKey(
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) {
    return '$candidate|${sdpMid ?? ''}|${sdpMLineIndex ?? -1}';
  }

  void dispose() {
    unawaited(close());
    _connectionStateController.close();
    _qualityController.close();
    _dataChannelHandler.dispose();
  }
}
