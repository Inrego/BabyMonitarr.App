import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/audio_state.dart';
import '../models/connection_state.dart';
import '../models/remote_ice_candidate.dart';
import '../services/audio_session_service.dart';
import '../services/notification_service.dart';
import '../services/signalr_service.dart';
import '../services/vibration_service.dart';
import '../services/webrtc_service.dart';
import 'audio_provider.dart';
import 'settings_provider.dart';

class ConnectionProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const Duration _watchdogInterval = Duration(seconds: 8);
  static const Duration _audioStallThreshold = Duration(seconds: 18);
  static const Duration _disconnectAlertThreshold = Duration(seconds: 30);
  static const Duration _minimumRecoveryGap = Duration(seconds: 6);

  final AudioSessionService _audioSession;
  final SignalRService _signalR;
  final NotificationService _notification;
  final VibrationService _vibration;

  ConnectionInfo _connectionInfo = const ConnectionInfo();
  AudioProvider? _audioProvider;
  SettingsProvider? _settingsProvider;
  bool _intentionalDisconnect = false;
  bool _isInBackground = false;
  bool _disposed = false;
  Future<void> _operationQueue = Future.value();

  final Map<int, _AudioRoomSession> _audioSessions = <int, _AudioRoomSession>{};
  Timer? _watchdogTimer;

  StreamSubscription? _signalRStateSub;
  StreamSubscription? _iceCandidateSub;

  ConnectionProvider({
    required AudioSessionService audioSession,
    SignalRService? signalR,
    NotificationService? notification,
    VibrationService? vibration,
  }) : _audioSession = audioSession,
       _signalR = signalR ?? SignalRService(),
       _notification = notification ?? NotificationService(),
       _vibration = vibration ?? VibrationService() {
    _initialize();
  }

  ConnectionInfo get connectionInfo => _connectionInfo;
  bool get isConnected => _signalR.isConnected;
  bool get isListening => _audioSessions.isNotEmpty;
  Set<int> get listeningRoomIds => _audioSessions.keys.toSet();

  // Backward-compatible getters used by existing widgets.
  int? get listeningRoomId =>
      _audioSessions.isEmpty ? null : _audioSessions.keys.first;
  bool get isAudioMuted {
    final roomId = listeningRoomId;
    if (roomId == null) return false;
    return _audioSessions[roomId]?.audioMuted ?? false;
  }

  SignalRService get signalR => _signalR;

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

      await _stopAllListeningInternal(resetAudioProvider: true);
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
    });
  }

  Future<void> disconnect() {
    return _runSerialized(() async {
      _intentionalDisconnect = true;
      await _stopAllListeningInternal(resetAudioProvider: true);
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

  bool isListeningToRoom(int roomId) => _audioSessions.containsKey(roomId);

  bool isAudioMutedForRoom(int roomId) =>
      _audioSessions[roomId]?.audioMuted ?? false;

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

      if (_audioSessions.containsKey(roomId)) {
        await _stopListeningToRoomInternal(roomId, resetAudioProvider: true);
        return;
      }

      final session = _createSession(roomId);
      _audioSessions[roomId] = session;

      try {
        await _signalR.selectRoom(roomId);
        await _startAudioWebRtcHandshake(session);

        session.audioMuted = false;
        session.webRtc.setAudioEnabled(true);
        _markAudioPacketReceived(session);
        _startWatchdog();
        await _refreshMonitoringNotification();
        unawaited(_notification.requestBatteryOptimizationExemption());
        await _persistActiveListeningRooms();

        _updateState(MonitorConnectionState.connected);
        notifyListeners();
      } catch (e) {
        await _disposeSession(roomId);
        _audioSessions.remove(roomId);
        await _refreshMonitoringNotification();
        await _persistActiveListeningRooms();
        _updateState(
          MonitorConnectionState.failed,
          error: 'Failed to start audio stream for room $roomId: $e',
        );
        rethrow;
      }
    });
  }

  Future<void> stopListeningToRoom(int roomId) {
    return _runSerialized(
      () => _stopListeningToRoomInternal(roomId, resetAudioProvider: true),
    );
  }

  Future<void> stopListening() {
    final roomId = listeningRoomId;
    if (roomId == null) return Future.value();
    return stopListeningToRoom(roomId);
  }

  Future<void> stopAllListening() {
    return _runSerialized(
      () => _stopAllListeningInternal(resetAudioProvider: true),
    );
  }

  Future<void> toggleAudioMuteForRoom(int roomId) async {
    final session = _audioSessions[roomId];
    if (session == null) return;
    session.audioMuted = !session.audioMuted;
    session.webRtc.setAudioEnabled(!session.audioMuted);
    notifyListeners();
  }

  Future<void> toggleAudioMute() async {
    final roomId = listeningRoomId;
    if (roomId == null) return;
    await toggleAudioMuteForRoom(roomId);
  }

  void setAudioEnabledForAll(bool enabled) {
    for (final session in _audioSessions.values) {
      session.audioMuted = !enabled;
      session.webRtc.setAudioEnabled(enabled);
    }
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

  _AudioRoomSession _createSession(int roomId) {
    final webRtc = WebRtcService();
    final session = _AudioRoomSession(roomId: roomId, webRtc: webRtc);

    session.webRtcStateSub = webRtc.connectionState.listen(
      (state) => _onWebRtcState(roomId, state),
    );
    session.qualitySub = webRtc.packetLossStream.listen(
      (loss) => _onPacketLoss(roomId, loss),
    );
    session.audioLevelSub = webRtc.dataChannelHandler.audioLevels.listen((
      level,
    ) {
      _markAudioPacketReceived(session);
      _audioProvider?.onAudioLevelForRoom(roomId, level);
    });
    session.soundAlertSub = webRtc.dataChannelHandler.soundAlerts.listen((
      alert,
    ) {
      _markAudioPacketReceived(session);
      _audioProvider?.onSoundAlertForRoom(roomId, alert);
      _handleSoundAlert(alert);
    });

    return session;
  }

  Future<void> _startAudioWebRtcHandshake(_AudioRoomSession session) async {
    await _audioSession.ensureConfigured();
    final rtcConfig = await _signalR.getWebRtcConfig();
    final sdpOffer = await _signalR.startAudioStream(session.roomId);
    final sdpAnswer = await session.webRtc.handleOffer(
      sdpOffer,
      onIceCandidate: (candidate) =>
          _onLocalIceCandidate(session.roomId, candidate),
      clientConfig: rtcConfig,
    );
    await _signalR.setAudioRemoteDescription(
      session.roomId,
      'answer',
      sdpAnswer,
    );
    await _audioSession.ensureConfigured();
  }

  Future<void> _stopListeningToRoomInternal(
    int roomId, {
    required bool resetAudioProvider,
  }) async {
    final session = _audioSessions[roomId];
    if (session == null) return;

    try {
      await _signalR.stopAudioStream(roomId);
    } catch (e) {
      debugPrint(
        'Stop listening room $roomId: failed to stop server stream: $e',
      );
    }

    await _disposeSession(roomId);
    _audioSessions.remove(roomId);

    if (_audioSessions.isEmpty) {
      try {
        await Helper.clearAndroidCommunicationDevice();
      } catch (e) {
        debugPrint('Stop listening: failed to clear Android audio device: $e');
      }
    }

    if (resetAudioProvider) {
      _audioProvider?.resetRoom(roomId);
    }

    await _persistActiveListeningRooms();
    await _refreshMonitoringNotification();
    _updateState(
      _audioSessions.isEmpty
          ? MonitorConnectionState.connected
          : _connectionInfo.state,
    );
    notifyListeners();
  }

  Future<void> _stopAllListeningInternal({
    required bool resetAudioProvider,
  }) async {
    final roomIds = _audioSessions.keys.toList(growable: false);
    for (final roomId in roomIds) {
      await _stopListeningToRoomInternal(
        roomId,
        resetAudioProvider: resetAudioProvider,
      );
    }
    if (resetAudioProvider) {
      _audioProvider?.resetAll();
    }
  }

  Future<void> _disposeSession(int roomId) async {
    final session = _audioSessions[roomId];
    if (session == null) return;
    await session.dispose();
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

  Future<void> _persistActiveListeningRooms() async {
    final settings = _settingsProvider;
    if (settings == null) return;
    try {
      await settings.setActiveListeningRoomIds(_audioSessions.keys.toSet());
    } catch (e) {
      debugPrint('Failed to persist active listening room ids: $e');
    }
  }

  Future<void> _refreshMonitoringNotification({
    bool reconnecting = false,
  }) async {
    final roomCount = _audioSessions.length;
    if (roomCount == 0) {
      _stopWatchdog();
      await _notification.stopMonitoringServiceNotification();
      await _notification.clearMonitoringDisconnectedNotification();
      return;
    }

    final onlyRoomId = roomCount == 1 ? _audioSessions.keys.first : null;
    await _notification.startMonitoringServiceNotification(
      reconnecting: reconnecting,
      roomId: onlyRoomId,
      roomCount: roomCount,
    );
  }

  void _markAudioPacketReceived(_AudioRoomSession session) {
    final now = DateTime.now();
    session.lastAudioPacketAt = now;
    session.lastMediaHeartbeatAt = now;
    session.signalRDisconnectedAt = null;
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
  }

  Future<void> _onWatchdogTick() async {
    if (_disposed || _intentionalDisconnect) return;
    if (_audioSessions.isEmpty) {
      _stopWatchdog();
      return;
    }

    final now = DateTime.now();
    final recoverRooms = <int>[];
    for (final session in _audioSessions.values) {
      final shouldRecover = _shouldRecoverFromWatchdog(session, now);
      if (shouldRecover) {
        recoverRooms.add(session.roomId);
      }
    }

    await _refreshMonitoringNotification(reconnecting: recoverRooms.isNotEmpty);

    if (recoverRooms.isEmpty) {
      await _notification.clearMonitoringDisconnectedNotification();
      return;
    }

    final oldestDisconnected = _audioSessions.values
        .map((s) => s.signalRDisconnectedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (current, next) {
          if (current == null) return next;
          return next.isBefore(current) ? next : current;
        });

    if (oldestDisconnected != null &&
        now.difference(oldestDisconnected) >= _disconnectAlertThreshold) {
      await _notification.showMonitoringDisconnectedNotification();
    }

    for (final roomId in recoverRooms) {
      await _recoverFromWatchdog(roomId);
    }
  }

  bool _shouldRecoverFromWatchdog(_AudioRoomSession session, DateTime now) {
    if (!_signalR.isConnected ||
        _connectionInfo.state == MonitorConnectionState.failed ||
        _connectionInfo.state == MonitorConnectionState.reconnecting) {
      session.signalRDisconnectedAt ??= now;
      return true;
    }

    DateTime? heartbeat = session.lastMediaHeartbeatAt;
    final audio = session.lastAudioPacketAt;
    if (heartbeat == null || (audio != null && audio.isAfter(heartbeat))) {
      heartbeat = audio;
    }
    if (heartbeat == null) {
      session.signalRDisconnectedAt ??= now;
      return true;
    }

    final isStalled = now.difference(heartbeat) >= _audioStallThreshold;
    if (isStalled) {
      session.signalRDisconnectedAt ??= now;
    }
    return isStalled;
  }

  Future<void> _recoverFromWatchdog(int roomId) async {
    final session = _audioSessions[roomId];
    if (session == null) return;
    if (session.watchdogRecoveryRunning) return;
    final now = DateTime.now();
    if (session.lastRecoveryAttemptAt != null &&
        now.difference(session.lastRecoveryAttemptAt!) < _minimumRecoveryGap) {
      return;
    }

    session.watchdogRecoveryRunning = true;
    session.lastRecoveryAttemptAt = now;
    try {
      await _runSerialized(() async {
        if (_disposed || _intentionalDisconnect) return;
        if (!_audioSessions.containsKey(roomId)) return;

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
          try {
            await _signalR.disconnect();
          } catch (e) {
            debugPrint('Watchdog reconnect: failed to disconnect SignalR: $e');
          }

          await _signalR.connect(SignalRService.normalizeServerUrl(serverUrl));
        }

        final current = _audioSessions[roomId];
        if (current == null) return;
        await _signalR.selectRoom(roomId);
        await current.webRtc.close();
        await _startAudioWebRtcHandshake(current);
        current.webRtc.setAudioEnabled(!current.audioMuted);
        _markAudioPacketReceived(current);
        _updateState(MonitorConnectionState.connected);
      });
    } catch (e) {
      _updateState(
        MonitorConnectionState.failed,
        error: 'Automatic recovery failed for room $roomId: $e',
      );
    } finally {
      final current = _audioSessions[roomId];
      if (current != null) {
        current.watchdogRecoveryRunning = false;
      }
    }
  }

  void _ensureSignalRSubscriptions() {
    _signalRStateSub ??= _signalR.connectionState.listen(_onSignalRState);
    _iceCandidateSub ??= _signalR.onIceCandidate.listen(_onRemoteIceCandidate);
  }

  void _onSignalRState(dynamic state) {
    if (_disposed || _intentionalDisconnect) return;
    final stateLabel = state.toString().toLowerCase();

    if (stateLabel.contains('reconnecting')) {
      for (final session in _audioSessions.values) {
        session.signalRDisconnectedAt ??= DateTime.now();
      }
      _updateState(MonitorConnectionState.reconnecting);
      unawaited(_refreshMonitoringNotification(reconnecting: true));
      return;
    }

    if (stateLabel.contains('disconnected')) {
      for (final session in _audioSessions.values) {
        session.signalRDisconnectedAt ??= DateTime.now();
      }
      _updateState(
        MonitorConnectionState.failed,
        error: 'SignalR disconnected',
      );
      if (_audioSessions.isNotEmpty) {
        _startWatchdog();
      }
      return;
    }

    if (stateLabel.contains('connected')) {
      for (final session in _audioSessions.values) {
        session.signalRDisconnectedAt = null;
      }
      _updateState(MonitorConnectionState.connected);
      if (_audioSessions.isNotEmpty) {
        _startWatchdog();
        unawaited(_refreshMonitoringNotification(reconnecting: false));
        unawaited(_notification.clearMonitoringDisconnectedNotification());
        unawaited(_restoreAudioAfterReconnect());
      }
    }
  }

  Future<void> _restoreAudioAfterReconnect() async {
    final roomIds = _audioSessions.keys.toList(growable: false);
    for (final roomId in roomIds) {
      final session = _audioSessions[roomId];
      if (session == null) continue;
      if (session.restoringAudioAfterReconnect ||
          session.watchdogRecoveryRunning) {
        continue;
      }

      session.restoringAudioAfterReconnect = true;
      try {
        await _runSerialized(() async {
          if (!_signalR.isConnected || _intentionalDisconnect || _disposed) {
            return;
          }
          if (!_audioSessions.containsKey(roomId)) return;
          await _signalR.selectRoom(roomId);
          await session.webRtc.close();
          await _startAudioWebRtcHandshake(session);
          session.webRtc.setAudioEnabled(!session.audioMuted);
          _markAudioPacketReceived(session);
          await _refreshMonitoringNotification();
          await _notification.clearMonitoringDisconnectedNotification();
        });
      } catch (e) {
        _updateState(
          MonitorConnectionState.failed,
          error: 'Failed restoring audio for room $roomId: $e',
        );
      } finally {
        session.restoringAudioAfterReconnect = false;
      }
    }
  }

  void _onWebRtcState(int roomId, RTCPeerConnectionState state) {
    if (_disposed || _intentionalDisconnect) return;
    final session = _audioSessions[roomId];
    if (session == null) return;

    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _markAudioPacketReceived(session);
        session.signalRDisconnectedAt = null;
        _updateState(MonitorConnectionState.connected);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        session.signalRDisconnectedAt ??= DateTime.now();
        if (_signalR.isConnected) {
          _updateState(
            MonitorConnectionState.failed,
            error: 'WebRTC state for room $roomId: ${state.name}',
          );
          _startWatchdog();
        }
        break;
      default:
        break;
    }
  }

  void _onPacketLoss(int roomId, double lossPercent) {
    final session = _audioSessions[roomId];
    if (session == null || _disposed) return;
    session.lastMediaHeartbeatAt = DateTime.now();

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
    if (_audioSessions.isEmpty || !_signalR.isConnected || _disposed) {
      return;
    }

    await _runSerialized(() async {
      if (_disposed || _intentionalDisconnect) return;
      if (!_signalR.isConnected) return;

      try {
        await _audioSession.ensureConfigured();
        for (final session in _audioSessions.values) {
          session.webRtc.setAudioEnabled(!session.audioMuted);
        }
      } catch (e) {
        debugPrint('Failed to recover audio session on resume: $e');
      }
    });
  }

  void _onRemoteIceCandidate(RemoteIceCandidate candidate) {
    if (_intentionalDisconnect || _disposed) return;
    final session = _audioSessions[candidate.roomId];
    if (session == null) {
      return;
    }
    unawaited(
      session.webRtc.addIceCandidate(
        candidate.candidate,
        candidate.sdpMid,
        candidate.sdpMLineIndex,
      ),
    );
  }

  void _onLocalIceCandidate(int roomId, RTCIceCandidate candidate) {
    final session = _audioSessions[roomId];
    if (session == null) return;

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
            debugPrint(
              'Failed to send local ICE candidate for room $roomId: $e',
            );
          }),
    );
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
            _refreshMonitoringNotification(
              reconnecting:
                  _connectionInfo.state != MonitorConnectionState.connected,
            ).catchError((e) {
              debugPrint('Failed to start monitoring foreground service: $e');
            }),
          );
        }
        break;
      case AppLifecycleState.resumed:
        _isInBackground = false;
        if (isListening) {
          unawaited(
            _refreshMonitoringNotification().catchError((e) {
              debugPrint('Failed to refresh monitoring foreground service: $e');
            }),
          );
          unawaited(_recoverAudioSessionAfterResume());
        } else {
          unawaited(_notification.stopMonitoringServiceNotification());
        }
        break;
      case AppLifecycleState.detached:
        _isInBackground = true;
        if (isListening) {
          _startWatchdog();
          unawaited(
            _refreshMonitoringNotification(
              reconnecting:
                  _connectionInfo.state != MonitorConnectionState.connected,
            ).catchError((e) {
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
    _cancelSignalRSubscriptions();
    for (final session in _audioSessions.values) {
      unawaited(session.dispose());
    }
    _audioSessions.clear();
    _signalR.dispose();
    super.dispose();
  }
}

class _AudioRoomSession {
  final int roomId;
  final WebRtcService webRtc;

  bool restoringAudioAfterReconnect = false;
  bool watchdogRecoveryRunning = false;
  bool audioMuted = false;

  DateTime? lastAudioPacketAt;
  DateTime? lastMediaHeartbeatAt;
  DateTime? signalRDisconnectedAt;
  DateTime? lastRecoveryAttemptAt;

  StreamSubscription? webRtcStateSub;
  StreamSubscription? qualitySub;
  StreamSubscription? audioLevelSub;
  StreamSubscription? soundAlertSub;

  _AudioRoomSession({required this.roomId, required this.webRtc});

  Future<void> dispose() async {
    await webRtcStateSub?.cancel();
    await qualitySub?.cancel();
    await audioLevelSub?.cancel();
    await soundAlertSub?.cancel();
    await webRtc.close();
    webRtc.dispose();
  }
}
