/// Local audio side effects of talking into a room: the platform audio
/// session and the room's incoming monitoring audio. Implemented by
/// `ConnectionProvider`.
abstract class TalkbackAudioControl {
  /// Switches to a play-and-record session and mutes [roomId]'s incoming
  /// audio so the camera doesn't feed the parent's voice back.
  Future<void> beginTalkback(int roomId);

  /// Restores the monitoring session and [roomId]'s audio.
  Future<void> endTalkback(int roomId);
}
