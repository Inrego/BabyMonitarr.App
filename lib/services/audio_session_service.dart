import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';

final _log = Logger('AudioSessionService');

class AudioSessionService {
  static final AndroidAudioConfiguration _androidMonitoringConfig =
      AndroidAudioConfiguration(
        // Let Android/media apps own focus transitions; this prevents
        // WebRTC playout from getting stuck after transient focus changes.
        manageAudioFocus: false,
        androidAudioMode: AndroidAudioMode.normal,
        androidAudioFocusMode: AndroidAudioFocusMode.gain,
        androidAudioStreamType: AndroidAudioStreamType.music,
        androidAudioAttributesUsageType: AndroidAudioAttributesUsageType.media,
        androidAudioAttributesContentType:
            AndroidAudioAttributesContentType.speech,
      );

  // While talking, the mic needs a voice-communication route so the platform
  // echo canceller runs. Monitoring playout for the talked-to room is muted
  // meanwhile, so the earpiece/speaker change doesn't matter to it.
  static final AndroidAudioConfiguration _androidTalkbackConfig =
      AndroidAudioConfiguration(
        manageAudioFocus: false,
        androidAudioMode: AndroidAudioMode.inCommunication,
        androidAudioFocusMode: AndroidAudioFocusMode.gain,
        androidAudioStreamType: AndroidAudioStreamType.voiceCall,
        androidAudioAttributesUsageType:
            AndroidAudioAttributesUsageType.voiceCommunication,
        androidAudioAttributesContentType:
            AndroidAudioAttributesContentType.speech,
      );

  bool _configured = false;
  bool _talkbackActive = false;

  bool get isTalkbackActive => _talkbackActive;

  /// Configures platform audio sessions for media playback (not voice call).
  /// Call once at app startup.
  Future<void> configureForMediaPlayback() async {
    await _applyPlatformConfig();
    _configured = true;
  }

  /// Re-applies audio configuration. Use before reconnecting WebRTC
  /// to ensure audio mode hasn't reverted. While talkback is active this keeps
  /// the play-and-record configuration, so a monitoring reconnect mid-talk
  /// doesn't cut the microphone.
  Future<void> ensureConfigured() async {
    await _applyPlatformConfig();
  }

  /// Switches to play-and-record / voice communication for talkback.
  Future<void> beginTalkback() async {
    _talkbackActive = true;
    await _applyPlatformConfig();
  }

  /// Restores the monitoring (playback-only) configuration.
  Future<void> endTalkback() async {
    if (!_talkbackActive) return;
    _talkbackActive = false;
    await _applyPlatformConfig();
  }

  Future<void> _ensureWebRtcInitialized() async {
    if (WebRTC.initialized) return;

    if (WebRTC.platformIsAndroid) {
      await WebRTC.initialize(
        options: {
          'androidAudioConfiguration': _androidMonitoringConfig.toMap(),
        },
      );
      return;
    }

    await WebRTC.initialize();
  }

  Future<void> _applyPlatformConfig() async {
    try {
      await _ensureWebRtcInitialized();

      if (WebRTC.platformIsAndroid) {
        await Helper.setAndroidAudioConfiguration(
          _talkbackActive ? _androidTalkbackConfig : _androidMonitoringConfig,
        );
      }

      if ((WebRTC.platformIsIOS || WebRTC.platformIsMacOS) && _talkbackActive) {
        await Helper.setAppleAudioConfiguration(
          AppleAudioConfiguration(
            appleAudioCategory: AppleAudioCategory.playAndRecord,
            appleAudioCategoryOptions: {
              AppleAudioCategoryOption.allowBluetooth,
              AppleAudioCategoryOption.allowBluetoothA2DP,
              AppleAudioCategoryOption.defaultToSpeaker,
            },
            appleAudioMode: AppleAudioMode.voiceChat,
          ),
        );
        await Helper.setAppleAudioIOMode(AppleAudioIOMode.localAndRemote);
      } else if (WebRTC.platformIsIOS || WebRTC.platformIsMacOS) {
        await Helper.setAppleAudioConfiguration(
          AppleAudioConfiguration(
            appleAudioCategory: AppleAudioCategory.playback,
            appleAudioCategoryOptions: {
              AppleAudioCategoryOption.allowBluetooth,
              AppleAudioCategoryOption.allowBluetoothA2DP,
              AppleAudioCategoryOption.allowAirPlay,
            },
            appleAudioMode: AppleAudioMode.spokenAudio,
          ),
        );
        await Helper.setAppleAudioIOMode(AppleAudioIOMode.remoteOnly);
      }
    } catch (e, st) {
      _log.warning('Failed to configure audio', e, st);
    }
  }

  bool get isConfigured => _configured;
}
