import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'data_channel_handler.dart';

class WebRtcService {
  RTCPeerConnection? _peerConnection;
  final DataChannelHandler _dataChannelHandler;
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;
  bool _audioEnabled = true;
  Timer? _statsTimer;

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

  Future<String> handleOffer(String sdpOffer) async {
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

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
      // Audio tracks auto-play through device speaker
    };

    _peerConnection!.onDataChannel = (channel) {
      debugPrint('WebRTC: Data channel opened: ${channel.label}');
      channel.onMessage = (message) {
        _dataChannelHandler.handleMessage(message.text);
      };
    };

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
      String candidate, String sdpMid, int? sdpMLineIndex) async {
    final iceCandidate = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);

    if (_remoteDescriptionSet && _peerConnection != null) {
      await _peerConnection!.addCandidate(iceCandidate);
    } else {
      _pendingCandidates.add(iceCandidate);
    }
  }

  Stream<RTCIceCandidate> get onLocalIceCandidate {
    final controller = StreamController<RTCIceCandidate>.broadcast();
    _peerConnection?.onIceCandidate = (candidate) {
      controller.add(candidate);
    };
    return controller.stream;
  }

  void setupIceCandidateCallback(
      void Function(RTCIceCandidate candidate) onCandidate) {
    _peerConnection?.onIceCandidate = onCandidate;
  }

  void toggleAudio() {
    _audioEnabled = !_audioEnabled;
    _setAudioEnabled(_audioEnabled);
  }

  void setAudioEnabled(bool enabled) {
    _audioEnabled = enabled;
    _setAudioEnabled(enabled);
  }

  Future<void> _setAudioEnabled(bool enabled) async {
    if (_peerConnection == null) return;
    try {
      final receivers = await _peerConnection!.getReceivers();
      for (final receiver in receivers.where(
          (r) => r.track != null && r.track!.kind == 'audio')) {
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
    _stopStatsPolling();
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    try {
      await _peerConnection?.close();
    } catch (e) {
      debugPrint('Error closing peer connection: $e');
    }
    _peerConnection = null;
  }

  void dispose() {
    close();
    _connectionStateController.close();
    _qualityController.close();
    _dataChannelHandler.dispose();
  }
}
