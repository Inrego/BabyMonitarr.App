import 'package:flutter_webrtc/flutter_webrtc.dart';

/// What to do with a video session that survived until the app resumed.
enum VideoResumeAction {
  /// Session is healthy and its renderer never left the foreground.
  keep,

  /// Peer connection is healthy, but the app was backgrounded: swap in a fresh
  /// renderer (fresh Android Surface) without restarting the stream.
  refreshRenderer,

  /// Session is broken: tear it down and start a new stream.
  rebuild,
}

/// Decides how to recover a video session on app resume.
///
/// [wasBackgrounded] is true when the app went through `hidden`/`paused`, as
/// opposed to only `inactive` (e.g. the notification shade was pulled down).
VideoResumeAction videoResumeAction({
  required bool wasBackgrounded,
  required RTCPeerConnectionState? connectionState,
  required bool isLoading,
  required bool hasStream,
  required bool hasError,
}) {
  if (hasError) return VideoResumeAction.rebuild;
  switch (connectionState) {
    case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
    case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
    case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
      return VideoResumeAction.rebuild;
    default:
      break;
  }
  // Still negotiating: leave it alone so it can finish.
  if (isLoading) return VideoResumeAction.keep;
  if (!hasStream) return VideoResumeAction.rebuild;
  return wasBackgrounded
      ? VideoResumeAction.refreshRenderer
      : VideoResumeAction.keep;
}
