class RemoteIceCandidate {
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  const RemoteIceCandidate({
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });
}
