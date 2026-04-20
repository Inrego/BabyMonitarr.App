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

  bool _configured = false;

  /// Configures platform audio sessions for media playback (not voice call).
  /// Call once at app startup.
  Future<void> configureForMediaPlayback() async {
    await _applyPlatformConfig();
    _configured = true;
  }

  /// Re-applies audio configuration. Use before reconnecting WebRTC
  /// to ensure audio mode hasn't reverted.
  Future<void> ensureConfigured() async {
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
        await Helper.setAndroidAudioConfiguration(_androidMonitoringConfig);
      }

      if (WebRTC.platformIsIOS || WebRTC.platformIsMacOS) {
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
