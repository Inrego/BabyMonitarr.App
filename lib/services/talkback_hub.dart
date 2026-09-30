import 'package:signalr_netcore/signalr_client.dart';
import '../models/remote_ice_candidate.dart';
import '../models/talkback_status.dart';
import '../models/webrtc_client_config.dart';

/// The slice of the `/audioHub` contract that talkback uses (see the backend's
/// docs/TALKBACK.md). Implemented by `SignalRService`; kept narrow so the
/// talkback provider can be tested against a fake.
abstract class TalkbackHub {
  bool get isConnected;
  Stream<HubConnectionState> get connectionState;
  Stream<TalkbackStatus> get onTalkbackStatusChanged;
  Stream<RemoteIceCandidate> get onTalkbackIceCandidate;

  Future<WebRtcClientConfig> getWebRtcConfig();
  Future<TalkbackStatus> getTalkbackStatus(int roomId);

  Future<String> startTalkbackUplink(int roomId);
  Future<void> setTalkbackRemoteDescription(
    int roomId,
    String type,
    String sdp,
  );
  Future<void> addTalkbackIceCandidate(
    int roomId,
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  );
  Future<void> stopTalkbackUplink(int roomId);

  Future<TalkbackStartResult> startTalkback(int roomId);
  Future<void> stopTalkback(int roomId);
  Future<void> setTalkbackVolume(int roomId, double volume);
}
