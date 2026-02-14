class RemoteVideoIceCandidate {
  final int roomId;
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  const RemoteVideoIceCandidate({
    required this.roomId,
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });
}
