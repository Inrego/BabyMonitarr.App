import 'dart:async';

import 'package:babymonitarr/models/remote_ice_candidate.dart';
import 'package:babymonitarr/models/talkback_status.dart';
import 'package:babymonitarr/models/webrtc_client_config.dart';
import 'package:babymonitarr/services/talkback_audio_control.dart';
import 'package:babymonitarr/services/talkback_hub.dart';
import 'package:babymonitarr/services/talkback_uplink_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:signalr_netcore/signalr_client.dart';

TalkbackStatus availableStatus(int roomId, {double volume = 1.0}) =>
    TalkbackStatus(
      roomId: roomId,
      supported: true,
      available: true,
      volume: volume,
    );

class FakeTalkbackHub implements TalkbackHub {
  final statusController = StreamController<TalkbackStatus>.broadcast();
  final iceController = StreamController<RemoteIceCandidate>.broadcast();
  final connectionController = StreamController<HubConnectionState>.broadcast();

  final List<String> calls = <String>[];
  final Map<int, TalkbackStatus> statuses = <int, TalkbackStatus>{};
  final List<double> volumes = <double>[];
  final List<String> localCandidates = <String>[];

  bool connected = true;
  Completer<TalkbackStartResult>? startCompleter;
  TalkbackStartResult startResult = const TalkbackStartResult(success: true);
  Object? startError;
  Object? uplinkError;

  @override
  bool get isConnected => connected;
  @override
  Stream<HubConnectionState> get connectionState => connectionController.stream;
  @override
  Stream<TalkbackStatus> get onTalkbackStatusChanged => statusController.stream;
  @override
  Stream<RemoteIceCandidate> get onTalkbackIceCandidate => iceController.stream;

  @override
  Future<WebRtcClientConfig> getWebRtcConfig() async =>
      WebRtcClientConfig.fallback();

  @override
  Future<TalkbackStatus> getTalkbackStatus(int roomId) async {
    calls.add('GetTalkbackStatus($roomId)');
    return statuses[roomId] ?? TalkbackStatus(roomId: roomId);
  }

  @override
  Future<String> startTalkbackUplink(int roomId) async {
    calls.add('StartTalkbackUplink($roomId)');
    if (uplinkError != null) throw uplinkError!;
    return 'offer-sdp';
  }

  @override
  Future<void> setTalkbackRemoteDescription(
    int roomId,
    String type,
    String sdp,
  ) async {
    calls.add('SetTalkbackRemoteDescription($roomId,$type,$sdp)');
  }

  @override
  Future<void> addTalkbackIceCandidate(
    int roomId,
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) async {
    localCandidates.add(candidate);
  }

  @override
  Future<void> stopTalkbackUplink(int roomId) async {
    calls.add('StopTalkbackUplink($roomId)');
  }

  @override
  Future<TalkbackStartResult> startTalkback(int roomId) async {
    calls.add('StartTalkback($roomId)');
    if (startError != null) throw startError!;
    if (startCompleter != null) return startCompleter!.future;
    return startResult;
  }

  @override
  Future<void> stopTalkback(int roomId) async {
    calls.add('StopTalkback($roomId)');
  }

  @override
  Future<void> setTalkbackVolume(int roomId, double volume) async {
    volumes.add(volume);
  }

  void dispose() {
    statusController.close();
    iceController.close();
    connectionController.close();
  }
}

class FakeAudioControl implements TalkbackAudioControl {
  final List<String> calls = <String>[];

  @override
  Future<void> beginTalkback(int roomId) async => calls.add('begin($roomId)');

  @override
  Future<void> endTalkback(int roomId) async => calls.add('end($roomId)');
}

class FakeUplink implements TalkbackUplink {
  bool closed = false;
  bool micFails = false;
  final List<String> remoteCandidates = <String>[];
  void Function(RTCIceCandidate candidate)? onIceCandidate;

  @override
  Future<String> handleOffer(
    String sdpOffer, {
    required void Function(RTCIceCandidate candidate) onIceCandidate,
    WebRtcClientConfig? clientConfig,
  }) async {
    this.onIceCandidate = onIceCandidate;
    if (micFails) throw const MicrophoneUnavailableException('denied');
    return 'answer-sdp';
  }

  @override
  Future<void> addRemoteCandidate(
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) async {
    remoteCandidates.add(candidate);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
