import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/connection_state.dart';
import '../models/audio_state.dart';
import '../models/remote_ice_candidate.dart';
import '../services/audio_session_service.dart';
import '../services/signalr_service.dart';
import '../services/webrtc_service.dart';
import '../services/notification_service.dart';
import '../services/vibration_service.dart';
import '../providers/audio_provider.dart';
import '../providers/settings_provider.dart';

class ConnectionProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const Duration _watchdogInterval = Duration(seconds: 8);
  static const Duration _audioStallThreshold = Duration(seconds: 18);
  static const Duration _disconnectAlertThreshold = Duration(seconds: 30);
  static const Duration _minimumRecoveryGap = Duration(seconds: 6);

  final AudioSessionService _audioSession;
  final SignalRService _signalR;
  final WebRtcService _webRtc;
  final NotificationService _notification;
  final VibrationService _vibration;

  ConnectionInfo _connectionInfo = const ConnectionInfo();
  AudioProvider? _audioProvider;
  SettingsProvider? _settingsProvider;
  bool _intentionalDisconnect = false;
  bool _isInBackground = false;
  bool _disposed = false;
  bool _restoringAudioAfterReconnect = false;
  bool _audioMuted = false;
  bool _watchdogRecoveryRunning = false;
  int? _listeningRoomId;
  Future<void> _operationQueue = Future.value();
  Timer? _watchdogTimer;
  DateTime? _lastAudioPacketAt;
  DateTime? _lastMediaHeartbeatAt;
  DateTime? _signalRDisconnectedAt;
  DateTime? _lastRecoveryAttemptAt;

  StreamSubscription? _signalRStateSub;
  StreamSubscription? _iceCandidateSub;
  StreamSubscription? _webRtcStateSub;
  StreamSubscription? _qualitySub;
  StreamSubscription? _audioLevelSub;
  StreamSubscription? _soundAlertSub;

  ConnectionProvider({
    required AudioSessionService audioSession,
    SignalRService? signalR,
    WebRtcService? webRtc,
    NotificationService? notification,
    VibrationService? vibration,
  }) : _audioSession = audioSession,
       _signalR = signalR ?? SignalRService(),
       _webRtc = webRtc ?? WebRtcService(),
       _notification = notification ?? NotificationService(),
       _vibration = vibration ?? VibrationService() {
    _initialize();
  }

  ConnectionInfo get connectionInfo => _connectionInfo;
  bool get isConnected => _signalR.isConnected;
  bool get isListening => _listeningRoomId != null;
  int? get listeningRoomId => _listeningRoomId;
  bool get isAudioMuted => _audioMuted;
  WebRtcService get webRtc => _webRtc;
  SignalRService get signalR => _signalR;

  Future<void> _initialize() async {
    WidgetsBinding.instance.addObserver(this);
    _webRtcStateSub = _webRtc.connectionState.listen(_onWebRtcState);
    _qualitySub = _webRtc.packetLossStream.listen(_onPacketLoss);
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

  Future<void> connect(String serverUrl) {
    return _runSerialized(() async {
      if (_disposed) return;

      final normalizedUrl = SignalRService.normalizeServerUrl(serverUrl);
      if (normalizedUrl.isEmpty) {
        _updateState(
          MonitorConnectionState.failed,
          error: 'Server URL is empty',
        );
        return;
      }

      _intentionalDisconnect = false;
      _updateState(MonitorConnectionState.connecting);
      _cancelSignalRSubscriptions();

      await _safeCloseWebRtc('Connect: failed to close previous WebRTC');
      await _signalR.disconnect();

      _signalRStateSub = _signalR.connectionState.listen(_onSignalRState);
      _iceCandidateSub = _signalR.onIceCandidate.listen(_onRemoteIceCandidate);

      try {
        await _signalR.connect(normalizedUrl);
        _updateState(MonitorConnectionState.connected);
      } catch (e) {
        _updateState(MonitorConnectionState.failed, error: e.toString());
        rethrow;
      }

      try {
        final settings = await _signalR.getAudioSettings();
        _settingsProvider?.updateAudioSettings(settings);
      } catch (e) {
        debugPrint('Failed to fetch audio settings: $e');
      }
    });
  }

  Future<void> disconnect() {
    return _runSerialized(() async {
      _intentionalDisconnect = true;
      await _stopListeningInternal(resetAudioProvider: true);
      _cancelSignalRSubscriptions();
      try {
        await _signalR.disconnect();
      } catch (e) {
        debugPrint('Disconnect: failed to disconnect SignalR: $e');
      }
      try {
        await _notification.cancelAll();
      } catch (e) {
        debugPrint('Disconnect: failed to cancel notifications: $e');
      }
      _updateState(MonitorConnectionState.disconnected);
    });
  }

  Future<void> startListeningToRoom(int roomId) {
    return _runSerialized(() async {
      if (_disposed) return;
      if (!_signalR.isConnected) {
        _updateState(
          MonitorConnectionState.failed,
          error: 'SignalR is not connected',
        );
        return;
      }

      if (_listeningRoomId == roomId) {
        await _stopListeningInternal(resetAudioProvider: true);
        return;
      }

      await _stopListeningInternal(resetAudioProvider: true);
      _updateState(MonitorConnectionState.connecting);

      try {
        await _signalR.selectRoom(roomId);
        _listeningRoomId = roomId;
        await _startAudioWebRtcHandshake(roomId);

        _audioMuted = false;
        _webRtc.setAudioEnabled(true);
        _markAudioPacketReceived();
        _startWatchdog();
        await _notification.startMonitoringServiceNotification(roomId: roomId);
        unawaited(_notification.requestBatteryOptimizationExemption());
        _persistActiveListeningRoom(roomId);

        _updateState(MonitorConnectionState.connected);
        notifyListeners();
      } catch (e) {
        _listeningRoomId = null;
        _stopWatchdog();
        _persistActiveListeningRoom(null);
        await _notification.stopMonitoringServiceNotification();
        _updateState(
          MonitorConnectionState.failed,
          error: 'Failed to start audio stream: $e',
        );
        rethrow;
      }
    });
  }

  Future<void> stopListening() {
    return _runSerialized(
      () => _stopListeningInternal(resetAudioProvider: true),
    );
  }

  Future<void> toggleAudioMute() async {
    if (_listeningRoomId == null) return;
    _audioMuted = !_audioMuted;
    _webRtc.setAudioEnabled(!_audioMuted);
    notifyListeners();
  }

  Future<void> syncAudioSettings() async {
    if (!_signalR.isConnected || _settingsProvider == null) return;
    try {
      await _signalR.updateAudioSettings(_settingsProvider!.audioSettings);
    } catch (e) {
      debugPrint('Failed to sync audio settings: $e');
    }
  }

  Future<void> _startAudioWebRtcHandshake(int roomId) async {
    await _audioSession.ensureConfigured();
    final sdpOffer = await _signalR.startAudioStream(roomId);
    final sdpAnswer = await _webRtc.handleOffer(
      sdpOffer,
      onIceCandidate: _onLocalIceCandidate,
    );
    await _signalR.setAudioRemoteDescription(roomId, 'answer', sdpAnswer);
    _subscribeToAudioStreams();
    await _audioSession.ensureConfigured();
  }

  Future<void> _stopListeningInternal({
    required bool resetAudioProvider,
  }) async {
    _stopWatchdog();

    final roomId = _listeningRoomId;
    try {
      if (roomId != null) {
        await _signalR.stopAudioStream(roomId);
      }
    } catch (e) {
      debugPrint('Stop listening: failed to stop server stream: $e');
    }

    await _safeCloseWebRtc('Stop listening: failed to close WebRTC');
    if (roomId != null) {
      try {
        await Helper.clearAndroidCommunicationDevice();
      } catch (e) {
        debugPrint('Stop listening: failed to clear Android audio device: $e');
      }
    }
    _listeningRoomId = null;
    _audioMuted = false;
    _persistActiveListeningRoom(null);
    await _notification.stopMonitoringServiceNotification();
    await _notification.clearMonitoringDisconnectedNotification();
    if (resetAudioProvider) {
      _audioProvider?.reset();
    }
    notifyListeners();
  }

  void _subscribeToAudioStreams() {
    _audioLevelSub?.cancel();
    _soundAlertSub?.cancel();

    _audioLevelSub = _webRtc.dataChannelHandler.audioLevels.listen((level) {
      _markAudioPacketReceived();
      _audioProvider?.onAudioLevel(level);
    });

    _soundAlertSub = _webRtc.dataChannelHandler.soundAlerts.listen((alert) {
      _markAudioPacketReceived();
      _audioProvider?.onSoundAlert(alert);
      _handleSoundAlert(alert);
    });
  }

  void _handleSoundAlert(SoundAlert alert) {
    if (_disposed) return;
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

  void _persistActiveListeningRoom(int? roomId) {
    final settings = _settingsProvider;
    if (settings == null) return;
    unawaited(
      settings.setActiveListeningRoomId(roomId).catchError((Object e) {
        debugPrint('Failed to persist active listening room id: $e');
      }),
    );
  }

  void _markAudioPacketReceived() {
    final now = DateTime.now();
    _lastAudioPacketAt = now;
    _lastMediaHeartbeatAt = now;
    _signalRDisconnectedAt = null;
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) {
      unawaited(_onWatchdogTick());
    });
    unawaited(_onWatchdogTick());
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _watchdogRecoveryRunning = false;
    _lastAudioPacketAt = null;
    _lastMediaHeartbeatAt = null;
    _signalRDisconnectedAt = null;
    _lastRecoveryAttemptAt = null;
  }

  Future<void> _onWatchdogTick() async {
    if (_disposed || _intentionalDisconnect) return;
    final roomId = _listeningRoomId;
    if (roomId == null) return;

    final now = DateTime.now();
    final needsRecovery = _shouldRecoverFromWatchdog(now);
    await _notification.startMonitoringServiceNotification(
      reconnecting: needsRecovery,
      roomId: roomId,
    );

    if (!needsRecovery) {
      _signalRDisconnectedAt = null;
      await _notification.clearMonitoringDisconnectedNotification();
      return;
    }

    final disconnectedAt = _signalRDisconnectedAt;
    if (disconnectedAt != null &&
        now.difference(disconnectedAt) >= _disconnectAlertThreshold) {
      await _notification.showMonitoringDisconnectedNotification(
        roomId: roomId,
      );
    }

    await _recoverFromWatchdog(roomId);
  }

  bool _shouldRecoverFromWatchdog(DateTime now) {
    if (!_signalR.isConnected ||
        _connectionInfo.state == MonitorConnectionState.failed ||
        _connectionInfo.state == MonitorConnectionState.reconnecting) {
      _signalRDisconnectedAt ??= now;
      return true;
    }

    DateTime? heartbeat = _lastMediaHeartbeatAt;
    final audio = _lastAudioPacketAt;
    if (heartbeat == null || (audio != null && audio.isAfter(heartbeat))) {
      heartbeat = audio;
    }
    if (heartbeat == null) {
      _signalRDisconnectedAt ??= now;
      return true;
    }

    final isStalled = now.difference(heartbeat) >= _audioStallThreshold;
    if (isStalled) {
      _signalRDisconnectedAt ??= now;
    }
    return isStalled;
  }

  Future<void> _recoverFromWatchdog(int roomId) async {
    if (_watchdogRecoveryRunning) return;
    final now = DateTime.now();
    if (_lastRecoveryAttemptAt != null &&
        now.difference(_lastRecoveryAttemptAt!) < _minimumRecoveryGap) {
      return;
    }

    _watchdogRecoveryRunning = true;
    _lastRecoveryAttemptAt = now;
    try {
      await _runSerialized(() async {
        if (_disposed || _intentionalDisconnect) return;
        if (_listeningRoomId != roomId) return;

        await _audioSession.ensureConfigured();

        if (!_signalR.isConnected) {
          final serverUrl = _settingsProvider?.serverUrl;
          if (serverUrl == null || serverUrl.trim().isEmpty) {
            _updateState(
              MonitorConnectionState.failed,
              error: 'Missing server URL for reconnect',
            );
            return;
          }

          _ensureSignalRSubscriptions();
          await _safeCloseWebRtc('Watchdog reconnect: failed to close WebRTC');

          try {
            await _signalR.disconnect();
          } catch (e) {
            debugPrint('Watchdog reconnect: failed to disconnect SignalR: $e');
          }

          await _signalR.connect(SignalRService.normalizeServerUrl(serverUrl));
        }

        await _signalR.selectRoom(roomId);
        await _startAudioWebRtcHandshake(roomId);
        _webRtc.setAudioEnabled(!_audioMuted);
        _markAudioPacketReceived();
        _persistActiveListeningRoom(roomId);
        _updateState(MonitorConnectionState.connected);
      });
    } catch (e) {
      _updateState(
        MonitorConnectionState.failed,
        error: 'Automatic recovery failed: $e',
      );
    } finally {
      _watchdogRecoveryRunning = false;
    }
  }

  void _ensureSignalRSubscriptions() {
    _signalRStateSub ??= _signalR.connectionState.listen(_onSignalRState);
    _iceCandidateSub ??= _signalR.onIceCandidate.listen(_onRemoteIceCandidate);
  }

  void _onSignalRState(dynamic state) {
    if (_disposed || _intentionalDisconnect) return;
    final stateLabel = state.toString().toLowerCase();
    final roomId = _listeningRoomId;

    if (stateLabel.contains('reconnecting')) {
      _signalRDisconnectedAt ??= DateTime.now();
      _updateState(MonitorConnectionState.reconnecting);
      if (roomId != null) {
        unawaited(
          _notification.startMonitoringServiceNotification(
            reconnecting: true,
            roomId: roomId,
          ),
        );
      }
      return;
    }

    if (stateLabel.contains('disconnected')) {
      _signalRDisconnectedAt ??= DateTime.now();
      _updateState(
        MonitorConnectionState.failed,
        error: 'SignalR disconnected',
      );
      if (roomId != null) {
        _startWatchdog();
      }
      return;
    }

    if (stateLabel.contains('connected')) {
      _signalRDisconnectedAt = null;
      _updateState(MonitorConnectionState.connected);
      if (roomId != null) {
        _startWatchdog();
        unawaited(
          _notification.startMonitoringServiceNotification(
            reconnecting: false,
            roomId: roomId,
          ),
        );
        unawaited(_notification.clearMonitoringDisconnectedNotification());
        if (!_watchdogRecoveryRunning) {
          unawaited(_restoreAudioAfterReconnect(roomId));
        }
      }
    }
  }

  Future<void> _restoreAudioAfterReconnect(int roomId) async {
    if (_restoringAudioAfterReconnect || _intentionalDisconnect || _disposed) {
      return;
    }
    _restoringAudioAfterReconnect = true;
    try {
      await _runSerialized(() async {
        if (!_signalR.isConnected || _intentionalDisconnect || _disposed) {
          return;
        }
        await _signalR.selectRoom(roomId);
        await _startAudioWebRtcHandshake(roomId);
        _webRtc.setAudioEnabled(!_audioMuted);
        _markAudioPacketReceived();
        _persistActiveListeningRoom(roomId);
        _startWatchdog();
        await _notification.startMonitoringServiceNotification(roomId: roomId);
        await _notification.clearMonitoringDisconnectedNotification();
      });
    } catch (e) {
      _updateState(
        MonitorConnectionState.failed,
        error: 'Failed restoring audio: $e',
      );
    } finally {
      _restoringAudioAfterReconnect = false;
    }
  }

  void _onWebRtcState(RTCPeerConnectionState state) {
    if (_disposed || _intentionalDisconnect) return;
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _markAudioPacketReceived();
        _signalRDisconnectedAt = null;
        _updateState(MonitorConnectionState.connected);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _signalRDisconnectedAt ??= DateTime.now();
        if (_listeningRoomId != null && _signalR.isConnected) {
          _updateState(
            MonitorConnectionState.failed,
            error: 'WebRTC state: ${state.name}',
          );
          _startWatchdog();
          unawaited(_restoreAudioAfterReconnect(_listeningRoomId!));
        }
        break;
      default:
        break;
    }
  }

  void _onPacketLoss(double lossPercent) {
    if (_disposed) return;
    _lastMediaHeartbeatAt = DateTime.now();
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

  Future<void> _recoverAudioSessionAfterResume() async {
    final roomId = _listeningRoomId;
    if (roomId == null || !_signalR.isConnected || _disposed) {
      return;
    }

    await _runSerialized(() async {
      if (_disposed || _intentionalDisconnect) return;
      if (_listeningRoomId != roomId || !_signalR.isConnected) return;

      try {
        await _audioSession.ensureConfigured();
        _webRtc.setAudioEnabled(!_audioMuted);
      } catch (e) {
        debugPrint('Failed to recover audio session on resume: $e');
      }
    });
  }

  void _onRemoteIceCandidate(RemoteIceCandidate candidate) {
    if (_intentionalDisconnect || _disposed) return;
    if (_listeningRoomId == null || candidate.roomId != _listeningRoomId) {
      return;
    }
    unawaited(
      _webRtc.addIceCandidate(
        candidate.candidate,
        candidate.sdpMid,
        candidate.sdpMLineIndex,
      ),
    );
  }

  void _onLocalIceCandidate(RTCIceCandidate candidate) {
    final roomId = _listeningRoomId;
    if (roomId == null) return;

    final rawCandidate = candidate.candidate;
    if (rawCandidate == null || rawCandidate.trim().isEmpty) return;
    if (WebRtcService.isLoopbackIceCandidate(rawCandidate)) return;

    unawaited(
      _signalR
          .addAudioIceCandidate(
            roomId,
            rawCandidate,
            candidate.sdpMid,
            candidate.sdpMLineIndex,
          )
          .catchError((Object e) {
            debugPrint('Failed to send local ICE candidate: $e');
          }),
    );
  }

  Future<void> _safeCloseWebRtc(String context) async {
    try {
      await _webRtc.close();
    } catch (e) {
      debugPrint('$context: $e');
    }
  }

  Future<void> _runSerialized(Future<void> Function() action) {
    final next = _operationQueue.then((_) => action());
    _operationQueue = next.catchError((_) {});
    return next;
  }

  void _updateState(MonitorConnectionState state, {String? error}) {
    if (_disposed) return;
    _connectionInfo = _connectionInfo.copyWith(
      state: state,
      errorMessage: error,
      reconnectAttempts: 0,
    );
    notifyListeners();
  }

  void _cancelSignalRSubscriptions() {
    _signalRStateSub?.cancel();
    _signalRStateSub = null;
    _iceCandidateSub?.cancel();
    _iceCandidateSub = null;
  }

  void _cancelAllSubscriptions() {
    _cancelSignalRSubscriptions();
    _webRtcStateSub?.cancel();
    _webRtcStateSub = null;
    _qualitySub?.cancel();
    _qualitySub = null;
    _audioLevelSub?.cancel();
    _audioLevelSub = null;
    _soundAlertSub?.cancel();
    _soundAlertSub = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _isInBackground = true;
        if (isListening) {
          _startWatchdog();
          unawaited(
            _notification
                .startMonitoringServiceNotification(
                  reconnecting:
                      _connectionInfo.state != MonitorConnectionState.connected,
                  roomId: _listeningRoomId,
                )
                .catchError((e) {
                  debugPrint(
                    'Failed to start monitoring foreground service: $e',
                  );
                }),
          );
        }
        break;
      case AppLifecycleState.resumed:
        _isInBackground = false;
<<<<<<< HEAD
        _notification.cancelForegroundNotification();
        if (isListening) {
          unawaited(_recoverAudioSessionAfterResume());
=======
        if (isListening) {
          unawaited(
            _notification
                .startMonitoringServiceNotification(roomId: _listeningRoomId)
                .catchError((e) {
                  debugPrint(
                    'Failed to refresh monitoring foreground service: $e',
                  );
                }),
          );
        } else {
          unawaited(_notification.stopMonitoringServiceNotification());
>>>>>>> features/persistant-audio-opencode-1-6ey
        }
        break;
      case AppLifecycleState.detached:
        _isInBackground = true;
        if (isListening) {
          _startWatchdog();
          unawaited(
            _notification
                .startMonitoringServiceNotification(
                  reconnecting:
                      _connectionInfo.state != MonitorConnectionState.connected,
                  roomId: _listeningRoomId,
                )
                .catchError((e) {
                  debugPrint('Failed to keep monitoring service on detach: $e');
                }),
          );
        }
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _stopWatchdog();
    unawaited(_notification.stopMonitoringServiceNotification());
    _cancelAllSubscriptions();
    _signalR.dispose();
    _webRtc.dispose();
    super.dispose();
  }
}
