import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/connection_state.dart';
import '../models/audio_state.dart';
import '../services/signalr_service.dart';
import '../services/webrtc_service.dart';
import '../services/notification_service.dart';
import '../services/vibration_service.dart';
import '../providers/audio_provider.dart';
import '../providers/settings_provider.dart';

class ConnectionProvider extends ChangeNotifier with WidgetsBindingObserver {
  final SignalRService _signalR;
  final WebRtcService _webRtc;
  final NotificationService _notification;
  final VibrationService _vibration;

  ConnectionInfo _connectionInfo = const ConnectionInfo();
  AudioProvider? _audioProvider;
  SettingsProvider? _settingsProvider;
  bool _intentionalDisconnect = false;
  bool _isInBackground = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  StreamSubscription? _signalRStateSub;
  StreamSubscription? _iceCandidateSub;
  StreamSubscription? _webRtcStateSub;
  StreamSubscription? _qualitySub;
  StreamSubscription? _audioLevelSub;
  StreamSubscription? _soundAlertSub;

  static const _backoffDurations = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ];

  ConnectionProvider({
    SignalRService? signalR,
    WebRtcService? webRtc,
    NotificationService? notification,
    VibrationService? vibration,
  })  : _signalR = signalR ?? SignalRService(),
        _webRtc = webRtc ?? WebRtcService(),
        _notification = notification ?? NotificationService(),
        _vibration = vibration ?? VibrationService() {
    _initialize();
  }

  ConnectionInfo get connectionInfo => _connectionInfo;
  bool get isConnected => _connectionInfo.isConnected;
  WebRtcService get webRtc => _webRtc;

  Future<void> _initialize() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      await _notification.initialize();
      await _vibration.initialize();
      await _notification.requestPermission();
    } catch (e) {
      debugPrint('Service initialization error: $e');
    }
  }

  void updateSettings(SettingsProvider settings) {
    _settingsProvider = settings;
    _vibration.enabled = settings.settings.vibrationEnabled;
  }

  void setAudioProvider(AudioProvider provider) {
    _audioProvider = provider;
    _subscribeToAudioStreams();
  }

  void _subscribeToAudioStreams() {
    _audioLevelSub?.cancel();
    _soundAlertSub?.cancel();

    _audioLevelSub =
        _webRtc.dataChannelHandler.audioLevels.listen((level) {
      _audioProvider?.onAudioLevel(level);
    });

    _soundAlertSub =
        _webRtc.dataChannelHandler.soundAlerts.listen((alert) {
      _audioProvider?.onSoundAlert(alert);
      _handleSoundAlert(alert);
    });
  }

  void _handleSoundAlert(SoundAlert alert) {
    if (_settingsProvider?.settings.vibrationEnabled ?? true) {
      _vibration.vibratePattern();
    }
    if (_isInBackground) {
      _notification.showAlertNotification(
        level: alert.level,
        threshold: alert.threshold,
      );
    }
  }

  Future<void> connect(String serverUrl) async {
    _intentionalDisconnect = false;
    _reconnectAttempts = 0;
    _updateState(MonitorConnectionState.connecting);

    try {
      // Subscribe to SignalR state changes
      _signalRStateSub?.cancel();
      _signalRStateSub = _signalR.connectionState.listen(_onSignalRState);

      // Connect SignalR
      await _signalR.connect(serverUrl);

      // Subscribe to ICE candidates from server
      _iceCandidateSub?.cancel();
      _iceCandidateSub = _signalR.onIceCandidate.listen((candidate) {
        _webRtc.addIceCandidate(
          candidate['candidate'] as String,
          candidate['sdpMid'] as String,
          candidate['sdpMLineIndex'] as int?,
        );
      });

      // Start WebRTC flow
      final sdpOffer = await _signalR.startWebRtcStream();
      final sdpAnswer = await _webRtc.handleOffer(sdpOffer);

      // Set up local ICE candidate forwarding
      _webRtc.setupIceCandidateCallback((candidate) {
        _signalR.addIceCandidate(
          candidate.candidate!,
          candidate.sdpMid!,
          candidate.sdpMLineIndex,
        );
      });

      // Send answer
      await _signalR.setRemoteDescription('answer', sdpAnswer);

      // Subscribe to WebRTC state
      _webRtcStateSub?.cancel();
      _webRtcStateSub = _webRtc.connectionState.listen(_onWebRtcState);

      // Subscribe to quality stats
      _qualitySub?.cancel();
      _qualitySub = _webRtc.packetLossStream.listen(_onPacketLoss);

      // Fetch audio settings
      try {
        final settings = await _signalR.getAudioSettings();
        _settingsProvider?.updateAudioSettings(settings);
      } catch (e) {
        debugPrint('Failed to fetch audio settings: $e');
      }

      _updateState(MonitorConnectionState.connected);
    } catch (e) {
      debugPrint('Connection error: $e');
      _updateState(MonitorConnectionState.failed,
          error: e.toString());
      _scheduleReconnect();
    }
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _cancelSubscriptions();
    await _signalR.stopWebRtcStream();
    await _webRtc.close();
    await _signalR.disconnect();
    _audioProvider?.reset();
    await _notification.cancelAll();
    _updateState(MonitorConnectionState.disconnected);
  }

  Future<void> syncAudioSettings() async {
    if (!isConnected || _settingsProvider == null) return;
    try {
      await _signalR
          .updateAudioSettings(_settingsProvider!.audioSettings);
    } catch (e) {
      debugPrint('Failed to sync audio settings: $e');
    }
  }

  void _onSignalRState(dynamic state) {
    // Handle reconnection states from SignalR
  }

  void _onWebRtcState(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _updateState(MonitorConnectionState.connected);
        _reconnectAttempts = 0;
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        if (!_intentionalDisconnect) {
          _updateState(MonitorConnectionState.reconnecting);
          _scheduleReconnect();
        }
        break;
      default:
        break;
    }
  }

  void _onPacketLoss(double lossPercent) {
    ConnectionQuality quality;
    if (lossPercent < 1) {
      quality = ConnectionQuality.strong;
    } else if (lossPercent < 5) {
      quality = ConnectionQuality.good;
    } else if (lossPercent < 10) {
      quality = ConnectionQuality.fair;
    } else {
      quality = ConnectionQuality.weak;
    }

    _connectionInfo = _connectionInfo.copyWith(
      quality: quality,
      packetLossPercent: lossPercent,
    );
    notifyListeners();
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;
    _reconnectTimer?.cancel();

    final backoffIndex =
        _reconnectAttempts.clamp(0, _backoffDurations.length - 1);
    final delay = _backoffDurations[backoffIndex];

    _reconnectTimer = Timer(delay, () async {
      if (_intentionalDisconnect) return;
      _reconnectAttempts++;
      _connectionInfo = _connectionInfo.copyWith(
        reconnectAttempts: _reconnectAttempts,
      );

      final url = _settingsProvider?.serverUrl;
      if (url != null && url.isNotEmpty) {
        _updateState(MonitorConnectionState.reconnecting);
        await _webRtc.close();
        await _signalR.disconnect();
        await connect(url);
      }
    });
  }

  void _updateState(MonitorConnectionState state, {String? error}) {
    _connectionInfo = _connectionInfo.copyWith(
      state: state,
      errorMessage: error,
    );
    notifyListeners();
  }

  void _cancelSubscriptions() {
    _signalRStateSub?.cancel();
    _iceCandidateSub?.cancel();
    _webRtcStateSub?.cancel();
    _qualitySub?.cancel();
    _audioLevelSub?.cancel();
    _soundAlertSub?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _isInBackground = true;
        if (isConnected) {
          _notification.showForegroundNotification();
        }
        break;
      case AppLifecycleState.resumed:
        _isInBackground = false;
        _notification.cancelForegroundNotification();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _cancelSubscriptions();
    _signalR.dispose();
    _webRtc.dispose();
    _notification.cancelAll();
    super.dispose();
  }
}
