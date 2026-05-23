import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';
import '../models/audio_state.dart';
import '../models/connection_state.dart';
import '../models/remote_ice_candidate.dart';
import '../services/audio_session_service.dart';
import '../services/notification_service.dart';
import '../services/signalr_service.dart';
import '../services/vibration_service.dart';
import '../services/webrtc_service.dart';
import 'audio_provider.dart';
import 'room_provider.dart';
import 'settings_provider.dart';

final _log = Logger('ConnectionProvider');

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
  RoomProvider? _roomProvider;
  SettingsProvider? _settingsProvider;
  bool _intentionalDisconnect = false;
  bool _disposed = false;
  Future<void> _operationQueue = Future.value();

  final Map<int, _AudioRoomSession> _audioSessions = <int, _AudioRoomSession>{};
  Timer? _watchdogTimer;

  Timer? _signalRReconnectTimer;
  int _signalRReconnectAttempts = 0;
  bool _signalRReconnectInFlight = false;

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
    } catch (e, st) {
      _log.severe('Service initialization error', e, st);
    }
  }

  void updateSettings(SettingsProvider settings) {
    _settingsProvider = settings;
    _vibration.enabled = settings.settings.vibrationEnabled;
  }

  void setAudioProvider(AudioProvider provider) {
    _audioProvider = provider;
  }

  void setRoomProvider(RoomProvider provider) {
    _roomProvider = provider;
  }

  Future<void> connect(String serverUrl) {
    return _runSerialized(() async {
      if (_disposed) return;

      _log.info('Connect requested');
      final normalizedUrl = SignalRService.normalizeServerUrl(serverUrl);
      if (normalizedUrl.isEmpty) {
        _updateState(
          MonitorConnectionState.failed,
          error: 'Server URL is empty',
        );
        return;
      }

      _intentionalDisconnect = false;
      _stopSignalRReconnectLoop();
      _updateState(MonitorConnectionState.connecting);
      _cancelSignalRSubscriptions();

      await _stopAllListeningInternal(resetAudioProvider: true);
      await _signalR.disconnect();

      _signalRStateSub = _signalR.connectionState.listen(_onSignalRState);
      _iceCandidateSub = _signalR.onIceCandidate.listen(_onRemoteIceCandidate);

      try {
        await _signalR.connect(
          normalizedUrl,
          apiKey: _settingsProvider?.apiKey,
        );
        _updateState(MonitorConnectionState.connected);
      } catch (e) {
        _updateState(MonitorConnectionState.failed, error: e.toString());
        rethrow;
      }
    });
  }

  Future<void> disconnect() {
    return _runSerialized(() async {
      _log.info('Disconnect requested');
      _intentionalDisconnect = true;
      _stopSignalRReconnectLoop();
      await _stopAllListeningInternal(resetAudioProvider: true);
      _cancelSignalRSubscriptions();
      try {
        await _signalR.disconnect();
      } catch (e, st) {
        _log.warning('Disconnect: failed to disconnect SignalR', e, st);
      }
      try {
        await _notification.cancelAll();
      } catch (e, st) {
        _log.warning('Disconnect: failed to cancel notifications', e, st);
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

      _log.info('Start listening to room $roomId');
      final session = _createSession(roomId);
      _audioSessions[roomId] = session;

      try {
        await _signalR.selectRoom(roomId);
        await _startAudioWebRtcHandshake(session);

        session.audioMuted = false;
        session.webRtc.setAudioEnabled(true);
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
    // Sync phase runs OUTSIDE `_runSerialized` so the UI flips, alerts stop
    // firing, and audio goes silent at button-press time regardless of what
    // else is queued (watchdog recovery, SignalR reconnect, a pending start).
    final session = _stopListeningSyncPhase(roomId, resetAudioProvider: true);
    if (session == null) return Future.value();
    // Heavy teardown stays serialized so a subsequent start/connect/disconnect
    // sees a fully closed peer connection.
    return _runSerialized(() => _stopListeningAsyncPhase(roomId, session));
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
    } catch (e, st) {
      _log.warning('Failed to sync audio settings', e, st);
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
      // Drop buffered events that race with a stop: sub.cancel() on a
      // broadcast stream doesn't drop already-scheduled deliveries.
      if (session.stopped || !identical(_audioSessions[roomId], session)) {
        return;
      }
      _markAudioPacketReceived(session);
      _audioProvider?.onAudioLevelForRoom(roomId, level);
    });
    session.soundAlertSub = webRtc.dataChannelHandler.soundAlerts.listen((
      alert,
    ) {
      if (session.stopped || !identical(_audioSessions[roomId], session)) {
        return;
      }
      _markAudioPacketReceived(session);
      _audioProvider?.onSoundAlertForRoom(roomId, alert);
      final roomName = _roomProvider?.roomById(roomId)?.name ?? 'Room $roomId';
      _handleSoundAlert(alert, roomName: roomName);
    });

    return session;
  }

  Future<void> _startAudioWebRtcHandshake(_AudioRoomSession session) async {
    final roomId = session.roomId;
    await _runHandshakeStep(
      'ensureAudioSession.pre',
      roomId,
      _audioSession.ensureConfigured,
    );
    final rtcConfig = await _runHandshakeStep(
      'getWebRtcConfig',
      roomId,
      _signalR.getWebRtcConfig,
    );
    final sdpOffer = await _runHandshakeStep(
      'startAudioStream',
      roomId,
      () => _signalR.startAudioStream(roomId),
    );
    final sdpAnswer = await _runHandshakeStep(
      'webRtc.handleOffer',
      roomId,
      () => session.webRtc.handleOffer(
        sdpOffer,
        onIceCandidate: (candidate) => _onLocalIceCandidate(roomId, candidate),
        clientConfig: rtcConfig,
      ),
    );
    await _runHandshakeStep(
      'setAudioRemoteDescription',
      roomId,
      () => _signalR.setAudioRemoteDescription(roomId, 'answer', sdpAnswer),
    );
    await _runHandshakeStep(
      'ensureAudioSession.post',
      roomId,
      _audioSession.ensureConfigured,
    );
  }

  Future<T> _runHandshakeStep<T>(
    String stepName,
    int roomId,
    Future<T> Function() action,
  ) async {
    _log.info('handshake[$roomId]: $stepName start');
    final sw = Stopwatch()..start();
    try {
      final result = await action();
      _log.info(
        'handshake[$roomId]: $stepName done in ${sw.elapsedMilliseconds}ms',
      );
      return result;
    } catch (e, st) {
      _log.warning(
        'handshake[$roomId]: $stepName failed after ${sw.elapsedMilliseconds}ms',
        e,
        st,
      );
      rethrow;
    }
  }

  /// Synchronous half of stopping a room. Pulls the session out of the active
  /// map, cancels its subscriptions, mutes its remote audio track, and flips
  /// UI state — all with zero awaits. Returns the removed session so the
  /// caller can hand it to [_stopListeningAsyncPhase] for heavy teardown, or
  /// `null` if the room wasn't active.
  _AudioRoomSession? _stopListeningSyncPhase(
    int roomId, {
    required bool resetAudioProvider,
  }) {
    final session = _audioSessions.remove(roomId);
    if (session == null) return null;

    _log.info('Stop listening to room $roomId');
    session.stopped = true;

    session.webRtcStateSub?.cancel();
    session.webRtcStateSub = null;
    session.qualitySub?.cancel();
    session.qualitySub = null;
    session.audioLevelSub?.cancel();
    session.audioLevelSub = null;
    session.soundAlertSub?.cancel();
    session.soundAlertSub = null;

    // Mute remote audio synchronously via the cached track refs — do NOT rely
    // on the async getReceivers() path, which races pc.close().
    session.webRtc.setAudioEnabled(false);

    if (resetAudioProvider) {
      _audioProvider?.resetRoom(roomId);
    }
    _updateState(
      _audioSessions.isEmpty
          ? MonitorConnectionState.connected
          : _connectionInfo.state,
    );
    notifyListeners();
    return session;
  }

  /// Background half of stopping a room: tears down the SignalR stream, the
  /// peer connection, platform audio routing, and persists state. Must be run
  /// serialized so a subsequent start/connect/disconnect sees a clean slate.
  Future<void> _stopListeningAsyncPhase(
    int roomId,
    _AudioRoomSession session,
  ) async {
    try {
      await _signalR.stopAudioStream(roomId);
    } catch (e, st) {
      _log.warning(
        'Stop listening room $roomId: failed to stop server stream',
        e,
        st,
      );
    }

    try {
      await session.dispose();
    } catch (e, st) {
      _log.warning(
        'Stop listening room $roomId: failed to dispose session',
        e,
        st,
      );
    }

    if (_audioSessions.isEmpty) {
      try {
        await Helper.clearAndroidCommunicationDevice();
      } catch (e, st) {
        _log.warning(
          'Stop listening: failed to clear Android audio device',
          e,
          st,
        );
      }
    }

    await _persistActiveListeningRooms();
    await _refreshMonitoringNotification();
  }

  /// Serialized stop used by internal callers (disconnect, stop-all, error
  /// recovery) that already run inside [_runSerialized]. Keeps the legacy
  /// "sync teardown + awaited heavy work in the same future" shape so the
  /// existing call sites don't need to change.
  Future<void> _stopListeningToRoomInternal(
    int roomId, {
    required bool resetAudioProvider,
  }) async {
    final session = _stopListeningSyncPhase(
      roomId,
      resetAudioProvider: resetAudioProvider,
    );
    if (session == null) return;
    await _stopListeningAsyncPhase(roomId, session);
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

  void _handleSoundAlert(SoundAlert alert, {required String roomName}) {
    if (_disposed) return;
    if (_settingsProvider?.settings.vibrationEnabled ?? true) {
      _vibration.vibratePattern();
    }
    _notification.showAlertNotification(
      level: alert.level,
      threshold: alert.threshold,
      roomName: roomName,
    );
  }

  Future<void> _persistActiveListeningRooms() async {
    final settings = _settingsProvider;
    if (settings == null) return;
    try {
      await settings.setActiveListeningRoomIds(_audioSessions.keys.toSet());
    } catch (e, st) {
      _log.warning('Failed to persist active listening room ids', e, st);
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

  void _ensureSignalRReconnectLoop() {
    if (_disposed || _intentionalDisconnect) return;
    if (_signalR.isConnected) return;
    final serverUrl = _settingsProvider?.serverUrl;
    if (serverUrl == null || serverUrl.trim().isEmpty) return;
    if (_signalRReconnectTimer != null || _signalRReconnectInFlight) return;
    _scheduleNextSignalRReconnectAttempt();
  }

  void _scheduleNextSignalRReconnectAttempt() {
    _signalRReconnectTimer?.cancel();
    final delayMs = SignalRService.reconnectDelayForAttempt(
      _signalRReconnectAttempts,
    );
    _signalRReconnectTimer = Timer(
      Duration(milliseconds: delayMs),
      () => unawaited(_attemptSignalRReconnect()),
    );
  }

  Future<void> _attemptSignalRReconnect() async {
    _signalRReconnectTimer = null;
    if (_disposed || _intentionalDisconnect || _signalR.isConnected) {
      _stopSignalRReconnectLoop();
      return;
    }
    _signalRReconnectInFlight = true;
    _signalRReconnectAttempts++;
    try {
      // Outer timeout is critical: if signalr_netcore's `start()` wedges
      // (the same dead-but-not-detected-transport class of bug that affects
      // hub invokes), the awaited future never returns and the `finally`
      // below never runs — `_signalRReconnectInFlight` would stick true
      // forever, blocking _ensureSignalRReconnectLoop from scheduling new
      // attempts. 30s covers a slow but legitimate negotiation while still
      // releasing us from a true wedge.
      await _runSerialized(() async {
        if (_disposed || _intentionalDisconnect || _signalR.isConnected) return;
        await _reconnectSignalRPreservingSessions();
      }).timeout(const Duration(seconds: 30));
    } catch (e, st) {
      _log.warning('SignalR reconnect attempt failed', e, st);
    } finally {
      _signalRReconnectInFlight = false;
    }
    if (_signalR.isConnected) {
      _stopSignalRReconnectLoop();
    } else if (!_disposed && !_intentionalDisconnect) {
      _scheduleNextSignalRReconnectAttempt();
    }
  }

  void _stopSignalRReconnectLoop() {
    _signalRReconnectTimer?.cancel();
    _signalRReconnectTimer = null;
    _signalRReconnectAttempts = 0;
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

  Future<void> _reconnectSignalRPreservingSessions() async {
    final serverUrl = _settingsProvider?.serverUrl;
    if (serverUrl == null || serverUrl.trim().isEmpty) {
      _updateState(
        MonitorConnectionState.failed,
        error: 'Missing server URL for reconnect',
      );
      return;
    }

    _ensureSignalRSubscriptions();
    _updateState(MonitorConnectionState.reconnecting);
    await _signalR.connect(
      SignalRService.normalizeServerUrl(serverUrl),
      apiKey: _settingsProvider?.apiKey,
    );
  }

  Future<void> _recoverFromWatchdog(int roomId) async {
    final session = _audioSessions[roomId];
    if (session == null) return;
    if (session.watchdogRecoveryRunning) return;
    if (session.restoringAudioAfterReconnect) return;
    final now = DateTime.now();
    if (session.lastRecoveryAttemptAt != null &&
        now.difference(session.lastRecoveryAttemptAt!) < _minimumRecoveryGap) {
      return;
    }

    final attempt = ++session.recoveryGeneration;
    _log.info('Watchdog recovery for room $roomId (attempt #$attempt)');
    session.watchdogRecoveryRunning = true;
    session.lastRecoveryAttemptAt = now;
    final sw = Stopwatch()..start();
    try {
      await _runSerialized(() async {
        // Defense-in-depth outer cap: the per-invoke 12s timeout in
        // SignalRService._invoke() is the primary protection against hung
        // hub calls, but this 15s outer cap also catches any non-SignalR
        // step that wedges (e.g. webRtc.close on flutter-webrtc native
        // disposal) and ensures the operation queue never deadlocks.
        await _recoverFromWatchdogBody(
          roomId,
          session,
          attempt,
          sw,
        ).timeout(const Duration(seconds: 15));
      });
    } catch (e, st) {
      _log.warning(
        'Watchdog recovery for room $roomId failed after ${sw.elapsedMilliseconds}ms',
        e,
        st,
      );
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

  Future<void> _recoverFromWatchdogBody(
    int roomId,
    _AudioRoomSession session,
    int attempt,
    Stopwatch sw,
  ) async {
    if (_disposed || _intentionalDisconnect) return;
    if (!_audioSessions.containsKey(roomId)) return;

    await _audioSession.ensureConfigured();

    if (!_signalR.isConnected) {
      await _reconnectSignalRPreservingSessions();
      if (!_signalR.isConnected) return;
    }

    final current = _audioSessions[roomId];
    if (current == null) return;
    await _signalR.selectRoom(roomId);
    // Best-effort: tell the server to drop its prior audio-stream state
    // before we ask it for a new one. stopAudioStream is wrapped in
    // try/catch and is a no-op when not connected, so it's safe to call.
    await _signalR.stopAudioStream(roomId);
    await current.webRtc.close();
    await _startAudioWebRtcHandshake(current);

    // Late-completion guard: if a newer attempt has started, or the
    // session has been replaced/removed, don't commit our side effects.
    if (attempt != current.recoveryGeneration ||
        !identical(_audioSessions[roomId], current)) {
      return;
    }
    current.webRtc.setAudioEnabled(!current.audioMuted);
    _markAudioPacketReceived(current);
    _updateState(MonitorConnectionState.connected);
    _log.info(
      'Watchdog recovery for room $roomId succeeded in ${sw.elapsedMilliseconds}ms',
    );
  }

  Future<void> _recoverConnectionAfterResume() async {
    final serverUrl = _settingsProvider?.serverUrl;
    if (_disposed ||
        _intentionalDisconnect ||
        serverUrl == null ||
        serverUrl.trim().isEmpty) {
      return;
    }

    await _runSerialized(() async {
      if (_disposed || _intentionalDisconnect) return;

      if (!_signalR.isConnected) {
        try {
          await _reconnectSignalRPreservingSessions();
        } catch (e, st) {
          _log.warning('Failed to reconnect SignalR on resume', e, st);
          _updateState(
            MonitorConnectionState.failed,
            error: 'Failed to reconnect after resume: $e',
          );
          if (isListening) {
            _startWatchdog();
          }
          _ensureSignalRReconnectLoop();
          return;
        }
      }

      if (isListening) {
        _startWatchdog();
        await _recoverAudioSessionAfterResume();
      }
    });
  }

  void _ensureSignalRSubscriptions() {
    _signalRStateSub ??= _signalR.connectionState.listen(_onSignalRState);
    _iceCandidateSub ??= _signalR.onIceCandidate.listen(_onRemoteIceCandidate);
  }

  void _onSignalRState(dynamic state) {
    if (_disposed || _intentionalDisconnect) return;
    final stateLabel = state.toString().toLowerCase();
    _log.info('SignalR state: $state (rooms=${_audioSessions.length})');

    if (stateLabel.contains('reconnecting')) {
      for (final session in _audioSessions.values) {
        session.signalRDisconnectedAt ??= DateTime.now();
        // Drop in-flight recovery flags — the SignalR transport just went
        // down, so any prior restore/watchdog work is no longer making
        // progress. Without this, a hung invoke from the previous attempt
        // would keep these flags set and skip every future restore.
        session.restoringAudioAfterReconnect = false;
        session.watchdogRecoveryRunning = false;
      }
      _updateState(MonitorConnectionState.reconnecting);
      unawaited(_refreshMonitoringNotification(reconnecting: true));
      // Defense-in-depth: after dropping withAutomaticReconnect we don't
      // expect Reconnecting to be emitted, but if anything ever drives the
      // state here we still want our manual loop running so the library
      // can't get stuck in a zombie Reconnecting state without anyone
      // driving recovery.
      _ensureSignalRReconnectLoop();
      return;
    }

    if (stateLabel.contains('disconnected')) {
      for (final session in _audioSessions.values) {
        session.signalRDisconnectedAt ??= DateTime.now();
        session.restoringAudioAfterReconnect = false;
        session.watchdogRecoveryRunning = false;
      }
      _updateState(
        MonitorConnectionState.failed,
        error: 'SignalR disconnected',
      );
      if (_audioSessions.isNotEmpty) {
        _startWatchdog();
      }
      _ensureSignalRReconnectLoop();
      return;
    }

    if (stateLabel.contains('connected')) {
      for (final session in _audioSessions.values) {
        session.signalRDisconnectedAt = null;
      }
      _stopSignalRReconnectLoop();
      _updateState(MonitorConnectionState.connected);
      if (_audioSessions.isNotEmpty) {
        // Claim each session for restore synchronously, BEFORE _startWatchdog
        // fires its immediate tick — otherwise the tick races and runs
        // _recoverFromWatchdog in parallel, and both paths fight over closing
        // and rebuilding the same peer connection.
        for (final session in _audioSessions.values) {
          if (!session.watchdogRecoveryRunning) {
            session.restoringAudioAfterReconnect = true;
          }
        }
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
      // The claim is now made synchronously by the caller in _onSignalRState
      // before _startWatchdog fires. If the flag isn't set, watchdog recovery
      // was already in flight for this session — skip and let it handle the
      // restore.
      if (!session.restoringAudioAfterReconnect) {
        continue;
      }

      final attempt = ++session.recoveryGeneration;
      _log.info(
        'Audio restore for room $roomId (attempt #$attempt)',
      );
      final sw = Stopwatch()..start();
      try {
        // If the existing peer connection is still Connected (it self-recovered
        // via ICE while SignalR was reconnecting) leave it alone — tearing it
        // down forces a fresh ICE negotiation that often fails on flaky links
        // and replaces a working stream with a broken one.
        if (session.webRtc.currentConnectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _log.info(
            'Skipping audio restore for room $roomId — peer connection still '
            'Connected',
          );
          // Defensive: the PC stayed up but the remote track may have been
          // left disabled by an earlier failed restore. Re-apply the desired
          // enabled state so the skip path can never silently mute audio.
          session.webRtc.setAudioEnabled(!session.audioMuted);
          _updateState(MonitorConnectionState.connected);
          await _refreshMonitoringNotification();
          await _notification.clearMonitoringDisconnectedNotification();
          continue;
        }

        await _runSerialized(() async {
          // Defense-in-depth outer cap (per-invoke 12s timeout in
          // SignalRService._invoke is the primary protection).
          await _restoreAudioBody(
            roomId,
            session,
            attempt,
            sw,
          ).timeout(const Duration(seconds: 15));
        });
      } catch (e, st) {
        _log.warning(
          'Audio restore for room $roomId failed after ${sw.elapsedMilliseconds}ms — will retry via watchdog',
          e,
          st,
        );
        _updateState(
          MonitorConnectionState.failed,
          error: 'Failed restoring audio for room $roomId: $e',
        );
      } finally {
        session.restoringAudioAfterReconnect = false;
      }
    }
  }

  Future<void> _restoreAudioBody(
    int roomId,
    _AudioRoomSession session,
    int attempt,
    Stopwatch sw,
  ) async {
    if (!_signalR.isConnected || _intentionalDisconnect || _disposed) {
      return;
    }
    if (!_audioSessions.containsKey(roomId)) return;
    await _signalR.selectRoom(roomId);
    // Best-effort: ask the server to drop the prior stream before we
    // start a new one. See same call in _recoverFromWatchdog.
    await _signalR.stopAudioStream(roomId);
    await session.webRtc.close();
    await _startAudioWebRtcHandshake(session);

    if (attempt != session.recoveryGeneration ||
        !identical(_audioSessions[roomId], session)) {
      return;
    }
    session.webRtc.setAudioEnabled(!session.audioMuted);
    _markAudioPacketReceived(session);
    await _refreshMonitoringNotification();
    await _notification.clearMonitoringDisconnectedNotification();
    _log.info(
      'Audio restore for room $roomId succeeded in ${sw.elapsedMilliseconds}ms',
    );
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

  /// Called from inside `_recoverConnectionAfterResume`'s `_runSerialized`
  /// block, so this function must NOT call `_runSerialized` again — doing so
  /// chains the inner future on the outer's completion and deadlocks the
  /// operation queue.
  ///
  /// Mirrors the video-side `_recoverVideoSessionsAfterResume` pattern: fully
  /// rebuild every audio peer connection, because flutter-webrtc's Android
  /// AudioTrack/playout binding can go stale across pause/resume and
  /// `setAudioEnabled` (just `MediaStreamTrack.enabled`) cannot revive it.
  Future<void> _recoverAudioSessionAfterResume() async {
    if (_audioSessions.isEmpty || !_signalR.isConnected || _disposed) {
      return;
    }

    final roomIds = _audioSessions.keys.toList(growable: false);
    _log.info('Resume: rebuilding audio sessions: $roomIds');

    for (final roomId in roomIds) {
      if (_disposed || _intentionalDisconnect) return;
      if (!_signalR.isConnected) return;

      final session = _audioSessions[roomId];
      if (session == null) continue;

      // If a reconnect-restore or watchdog recovery is already rebuilding
      // this session, let it finish — racing it would double-close the peer
      // connection.
      if (session.restoringAudioAfterReconnect ||
          session.watchdogRecoveryRunning ||
          session.resumeRebuildRunning) {
        continue;
      }

      session.resumeRebuildRunning = true;
      final attempt = ++session.recoveryGeneration;
      final sw = Stopwatch()..start();
      _log.info('Resume audio rebuild for room $roomId (attempt #$attempt)');
      try {
        await _resumeRebuildBody(
          roomId,
          session,
          attempt,
          sw,
        ).timeout(const Duration(seconds: 15));
      } catch (e, st) {
        _log.warning(
          'Resume audio rebuild for room $roomId failed after '
          '${sw.elapsedMilliseconds}ms — will retry via watchdog',
          e,
          st,
        );
        _updateState(
          MonitorConnectionState.failed,
          error: 'Failed rebuilding audio for room $roomId: $e',
        );
      } finally {
        // Reread — the session may have been replaced or removed during the
        // rebuild; only clear the flag on the still-current instance.
        final current = _audioSessions[roomId];
        if (current != null) {
          current.resumeRebuildRunning = false;
        }
      }
    }
  }

  Future<void> _resumeRebuildBody(
    int roomId,
    _AudioRoomSession session,
    int attempt,
    Stopwatch sw,
  ) async {
    if (!_signalR.isConnected || _intentionalDisconnect || _disposed) return;
    if (!_audioSessions.containsKey(roomId)) return;

    await _signalR.selectRoom(roomId);
    // Best-effort: ask the server to drop the prior stream before we start
    // a new one. Same as `_restoreAudioBody`.
    await _signalR.stopAudioStream(roomId);
    await session.webRtc.close();
    await _startAudioWebRtcHandshake(session);

    // Late-completion guard: a newer attempt (watchdog, reconnect, another
    // resume) may have superseded us, or the session may have been replaced.
    if (attempt != session.recoveryGeneration ||
        !identical(_audioSessions[roomId], session)) {
      return;
    }
    session.webRtc.setAudioEnabled(!session.audioMuted);
    _markAudioPacketReceived(session);
    _log.info(
      'Resume audio rebuild for room $roomId succeeded in '
      '${sw.elapsedMilliseconds}ms',
    );
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
          .catchError((Object e, StackTrace st) {
            _log.warning(
              'Failed to send local ICE candidate for room $roomId',
              e,
              st,
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
        if (isListening) {
          _startWatchdog();
          unawaited(
            _refreshMonitoringNotification(
              reconnecting:
                  _connectionInfo.state != MonitorConnectionState.connected,
            ).catchError((e, st) {
              _log.warning(
                'Failed to start monitoring foreground service',
                e,
                st,
              );
            }),
          );
        }
        break;
      case AppLifecycleState.resumed:
        if (isListening) {
          unawaited(
            _refreshMonitoringNotification().catchError((e, st) {
              _log.warning(
                'Failed to refresh monitoring foreground service',
                e,
                st,
              );
            }),
          );
        } else {
          unawaited(_notification.stopMonitoringServiceNotification());
        }
        unawaited(_recoverConnectionAfterResume());
        break;
      case AppLifecycleState.detached:
        if (isListening) {
          _startWatchdog();
          unawaited(
            _refreshMonitoringNotification(
              reconnecting:
                  _connectionInfo.state != MonitorConnectionState.connected,
            ).catchError((e, st) {
              _log.warning(
                'Failed to keep monitoring service on detach',
                e,
                st,
              );
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
    _stopSignalRReconnectLoop();
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
  bool resumeRebuildRunning = false;
  bool audioMuted = false;
  // Bumped on every recovery attempt. A `.timeout()` that fires after the
  // underlying SignalR/WebRTC call eventually returns must NOT commit side
  // effects belonging to a stale attempt — comparing against this generation
  // catches that.
  int recoveryGeneration = 0;
  // Set to true by the stop path's sync phase so buffered broadcast-stream
  // events arriving between sub.cancel() and actual unsubscribe can't
  // re-trigger notifications, vibration, VU meters, or alert state.
  bool stopped = false;

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
