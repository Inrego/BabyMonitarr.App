import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/connection_state.dart';
import '../models/audio_state.dart';
import '../models/remote_ice_candidate.dart';
import '../services/signalr_service.dart';
import '../services/webrtc_service.dart';
import '../services/notification_service.dart';
import '../services/vibration_service.dart';
import '../providers/audio_provider.dart';
import '../providers/settings_provider.dart';

class _WebRtcAttemptContext {
  final int id;
  final DateTime startedAt;
  bool isActive = true;
  int localIceCount = 0;
  int remoteIceCount = 0;
  String? expectedRemoteUfrag;
  DateTime? firstLocalIceAt;
  DateTime? firstRemoteIceAt;
  bool stageBStarted = false;

  _WebRtcAttemptContext(this.id) : startedAt = DateTime.now();
}

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
  bool _disposed = false;
  Timer? _reconnectTimer;
  Timer? _stageACandidateTimer;
  Timer? _stageBConnectTimer;
  int _reconnectAttempts = 0;
  int _webRtcRetryAttempts = 0;
  bool _webRtcRetryInFlight = false;
  Future<void>? _disconnectInFlight;
  Future<void> _operationQueue = Future.value();
  int _attemptCounter = 0;
  _WebRtcAttemptContext? _attempt;

  StreamSubscription? _signalRStateSub;
  StreamSubscription? _iceCandidateSub;
  StreamSubscription? _webRtcStateSub;
  StreamSubscription? _qualitySub;
  StreamSubscription? _audioLevelSub;
  StreamSubscription? _soundAlertSub;

  static const _stageACandidateTimeout = Duration(seconds: 3);
  static const _stageBConnectTimeout = Duration(seconds: 5);
  static const _maxWebRtcRetries = 3;
  static const _webRtcRetryDelay = Duration(milliseconds: 500);

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
  }) : _signalR = signalR ?? SignalRService(),
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

    _audioLevelSub = _webRtc.dataChannelHandler.audioLevels.listen((level) {
      _audioProvider?.onAudioLevel(level);
    });

    _soundAlertSub = _webRtc.dataChannelHandler.soundAlerts.listen((alert) {
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

  Future<void> connect(String serverUrl) {
    return _runSerialized(
      () => _connectInternal(
        serverUrl: serverUrl,
        resetBackoff: true,
        fetchSettings: true,
        isRetryAttempt: false,
      ),
    );
  }

  Future<void> _connectInternal({
    required String serverUrl,
    required bool resetBackoff,
    required bool fetchSettings,
    required bool isRetryAttempt,
  }) async {
    if (_disposed) return;

    final trimmedServerUrl = serverUrl.trim();
    if (trimmedServerUrl.isEmpty) {
      _updateState(MonitorConnectionState.failed, error: 'Server URL is empty');
      return;
    }

    if (resetBackoff) {
      _reconnectAttempts = 0;
      _webRtcRetryAttempts = 0;
    }

    _intentionalDisconnect = false;
    _cancelReconnectTimer();
    _deactivateCurrentAttempt();

    if (!isRetryAttempt) {
      _cancelSubscriptions();
      await _safeCloseWebRtc(
        'Connect: failed to close previous peer connection',
      );
      _updateState(MonitorConnectionState.connecting);

      _signalRStateSub = _signalR.connectionState.listen(_onSignalRState);
      await _signalR.connect(trimmedServerUrl);
      _iceCandidateSub = _signalR.onIceCandidate.listen(_onRemoteIceCandidate);
    } else {
      _updateState(MonitorConnectionState.reconnecting);
      _webRtcStateSub?.cancel();
      _webRtcStateSub = null;
      _qualitySub?.cancel();
      _qualitySub = null;

      try {
        await _signalR.stopWebRtcStream();
      } catch (e) {
        debugPrint('WebRTC retry: failed to stop server stream: $e');
      }

      await _safeCloseWebRtc('WebRTC retry: failed to close peer connection');
      await Future.delayed(_webRtcRetryDelay);
      if (_disposed || _intentionalDisconnect || !_signalR.isConnected) {
        _scheduleReconnect();
        return;
      }
    }

    final attempt = _startAttempt();
    _logAttemptEvent(
      attempt.id,
      'attempt_started',
      details: {
        'retry': isRetryAttempt,
        'signalrConnected': _signalR.isConnected,
      },
    );

    _webRtcStateSub = _webRtc.connectionState.listen(
      (state) => _onWebRtcState(state, attempt.id),
    );
    _qualitySub = _webRtc.packetLossStream.listen(_onPacketLoss);

    try {
      final sdpOffer = await _signalR.startWebRtcStream();
      if (!_isAttemptCurrent(attempt.id)) return;
      attempt.expectedRemoteUfrag = _extractRemoteUfragFromSdp(sdpOffer);
      _logAttemptEvent(attempt.id, 'offer_received');

      final sdpAnswer = await _webRtc.handleOffer(
        sdpOffer,
        onIceCandidate: (candidate) =>
            _onLocalIceCandidate(candidate, attempt.id),
      );
      if (!_isAttemptCurrent(attempt.id)) return;

      await _signalR.setRemoteDescription('answer', sdpAnswer);
      if (!_isAttemptCurrent(attempt.id)) return;

      _logAttemptEvent(attempt.id, 'answer_sent');
      _subscribeToAudioStreams();

      if (fetchSettings) {
        try {
          final settings = await _signalR.getAudioSettings();
          _settingsProvider?.updateAudioSettings(settings);
        } catch (e) {
          debugPrint('Failed to fetch audio settings: $e');
        }
      }

      _startStageATimeout(attempt.id);
    } catch (e) {
      if (!_isAttemptCurrent(attempt.id)) return;
      _logAttemptEvent(
        attempt.id,
        'attempt_error',
        details: {'error': e.toString()},
      );
      _updateState(MonitorConnectionState.failed, error: e.toString());
      _scheduleRecovery(attempt.id, reason: 'connect_error');
    }
  }

  Future<void> disconnect() {
    final inFlight = _disconnectInFlight;
    if (inFlight != null) return inFlight;

    final operation = _runSerialized(_performDisconnect);
    _disconnectInFlight = operation;

    return operation.whenComplete(() {
      _disconnectInFlight = null;
    });
  }

  Future<void> _performDisconnect() async {
    _intentionalDisconnect = true;
    _cancelReconnectTimer();
    _deactivateCurrentAttempt();
    _webRtcRetryInFlight = false;
    _cancelSubscriptions();

    try {
      await _signalR.stopWebRtcStream();
    } catch (e) {
      debugPrint('Disconnect: failed to stop WebRTC stream: $e');
    }

    await _safeCloseWebRtc('Disconnect: failed to close WebRTC');

    try {
      await _signalR.disconnect();
    } catch (e) {
      debugPrint('Disconnect: failed to disconnect SignalR: $e');
    }

    try {
      _audioProvider?.reset();
    } catch (e) {
      debugPrint('Disconnect: failed to reset audio: $e');
    }

    try {
      await _notification.cancelAll();
    } catch (e) {
      debugPrint('Disconnect: failed to cancel notifications: $e');
    }

    _updateState(MonitorConnectionState.disconnected);
  }

  Future<void> syncAudioSettings() async {
    if (!isConnected || _settingsProvider == null) return;
    try {
      await _signalR.updateAudioSettings(_settingsProvider!.audioSettings);
    } catch (e) {
      debugPrint('Failed to sync audio settings: $e');
    }
  }

  void _onSignalRState(dynamic state) {
    if (_disposed || _intentionalDisconnect) return;
    final stateLabel = state.toString().toLowerCase();

    if (stateLabel.contains('reconnecting')) {
      _updateState(MonitorConnectionState.reconnecting);
      return;
    }

    if (stateLabel.contains('disconnected') &&
        _connectionInfo.state != MonitorConnectionState.disconnected) {
      _updateState(
        MonitorConnectionState.failed,
        error: 'SignalR disconnected',
      );
      _scheduleReconnect();
    }
  }

  void _onWebRtcState(RTCPeerConnectionState state, int attemptId) {
    if (!_isAttemptCurrent(attemptId)) {
      return;
    }

    _logAttemptEvent(
      attemptId,
      'pc_state_change',
      details: {'state': state.name},
    );

    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _cancelWebRtcAttemptTimers();
        _updateState(MonitorConnectionState.connected);
        _reconnectAttempts = 0;
        _webRtcRetryAttempts = 0;
        _logAttemptEvent(
          attemptId,
          'connected',
          details: {
            'localCandidates': _attempt?.localIceCount,
            'remoteCandidates': _attempt?.remoteIceCount,
          },
        );
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _cancelWebRtcAttemptTimers();
        _updateState(
          MonitorConnectionState.failed,
          error: 'WebRTC state: ${state.name}',
        );
        _scheduleRecovery(attemptId, reason: 'pc_${state.name}');
        break;
      default:
        break;
    }
  }

  void _onPacketLoss(double lossPercent) {
    if (_disposed) return;
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
    if (_intentionalDisconnect || _disposed) return;
    _deactivateCurrentAttempt();
    _reconnectTimer?.cancel();
    _webRtcRetryAttempts = 0;

    final backoffIndex = _reconnectAttempts.clamp(
      0,
      _backoffDurations.length - 1,
    );
    final delay = _backoffDurations[backoffIndex];

    _reconnectTimer = Timer(delay, () {
      if (_intentionalDisconnect || _disposed) return;
      _reconnectAttempts++;
      _connectionInfo = _connectionInfo.copyWith(
        reconnectAttempts: _reconnectAttempts,
      );
      notifyListeners();

      final url = _settingsProvider?.serverUrl;
      if (url != null && url.isNotEmpty) {
        _updateState(MonitorConnectionState.reconnecting);
        _audioProvider?.reset();
        unawaited(connect(url));
      }
    });
  }

  void _scheduleRecovery(int attemptId, {required String reason}) {
    if (_intentionalDisconnect || _disposed) return;
    unawaited(_runSerialized(() => _recoverAttempt(attemptId, reason)));
  }

  Future<void> _recoverAttempt(int attemptId, String reason) async {
    if (!_isAttemptCurrent(attemptId) || _intentionalDisconnect || _disposed) {
      return;
    }

    if (_signalR.isConnected && _webRtcRetryAttempts < _maxWebRtcRetries) {
      await _retryWebRtcOnly(attemptId, reason: reason);
      return;
    }

    _logAttemptEvent(
      attemptId,
      'fallback_reconnect',
      details: {'reason': reason},
    );
    _updateState(MonitorConnectionState.reconnecting);
    _scheduleReconnect();
  }

  Future<void> _retryWebRtcOnly(int attemptId, {required String reason}) async {
    if (_webRtcRetryInFlight || _intentionalDisconnect || _disposed) return;
    if (!_isAttemptCurrent(attemptId)) return;

    final url = _settingsProvider?.serverUrl;
    if (url == null || url.isEmpty) {
      _scheduleReconnect();
      return;
    }

    _webRtcRetryInFlight = true;

    try {
      _webRtcRetryAttempts++;
      _logAttemptEvent(
        attemptId,
        'retry_webrtc_only',
        details: {
          'reason': reason,
          'attempt': _webRtcRetryAttempts,
          'maxAttempts': _maxWebRtcRetries,
        },
      );
      await _connectInternal(
        serverUrl: url,
        resetBackoff: false,
        fetchSettings: false,
        isRetryAttempt: true,
      );
    } finally {
      _webRtcRetryInFlight = false;
    }
  }

  void _onRemoteIceCandidate(RemoteIceCandidate candidate) {
    final attempt = _attempt;
    if (attempt == null || !attempt.isActive) return;
    if (_intentionalDisconnect || _disposed) return;

    final candidateUfrag = _extractUfragFromCandidate(candidate.candidate);
    if (attempt.expectedRemoteUfrag != null &&
        candidateUfrag != null &&
        candidateUfrag != attempt.expectedRemoteUfrag) {
      _logAttemptEvent(
        attempt.id,
        'remote_candidate_dropped_ufrag_mismatch',
        details: {
          'candidateUfrag': candidateUfrag,
          'expectedUfrag': attempt.expectedRemoteUfrag,
        },
      );
      return;
    }

    if (WebRtcService.isLoopbackIceCandidate(candidate.candidate)) {
      _logAttemptEvent(attempt.id, 'remote_candidate_dropped_loopback');
      return;
    }

    attempt.remoteIceCount++;
    if (attempt.firstRemoteIceAt == null) {
      attempt.firstRemoteIceAt = DateTime.now();
      _logAttemptEvent(attempt.id, 'first_remote_candidate');
      _startStageBTimeout(attempt.id);
    }

    unawaited(
      _webRtc
          .addIceCandidate(
            candidate.candidate,
            candidate.sdpMid,
            candidate.sdpMLineIndex,
          )
          .catchError((Object error) {
            if (_isAttemptCurrent(attempt.id)) {
              _logAttemptEvent(
                attempt.id,
                'remote_candidate_add_error',
                details: {'error': error.toString()},
              );
            }
          }),
    );
  }

  void _onLocalIceCandidate(RTCIceCandidate candidate, int attemptId) {
    if (!_isAttemptCurrent(attemptId)) return;
    final rawCandidate = candidate.candidate;
    if (rawCandidate == null || rawCandidate.trim().isEmpty) {
      return;
    }

    if (WebRtcService.isLoopbackIceCandidate(rawCandidate)) {
      _logAttemptEvent(attemptId, 'local_candidate_dropped_loopback');
      return;
    }

    final attempt = _attempt;
    if (attempt != null && attempt.id == attemptId) {
      attempt.localIceCount++;
      if (attempt.firstLocalIceAt == null) {
        attempt.firstLocalIceAt = DateTime.now();
        _logAttemptEvent(attemptId, 'first_local_candidate');
      }
    }

    unawaited(
      _signalR
          .addIceCandidate(
            rawCandidate,
            candidate.sdpMid,
            candidate.sdpMLineIndex,
          )
          .catchError((Object error) {
            if (_isAttemptCurrent(attemptId)) {
              _logAttemptEvent(
                attemptId,
                'local_candidate_send_error',
                details: {'error': error.toString()},
              );
            }
          }),
    );
  }

  _WebRtcAttemptContext _startAttempt() {
    _deactivateCurrentAttempt();
    final attempt = _WebRtcAttemptContext(++_attemptCounter);
    _attempt = attempt;
    return attempt;
  }

  bool _isAttemptCurrent(int attemptId) {
    final attempt = _attempt;
    return attempt != null &&
        attempt.isActive &&
        attempt.id == attemptId &&
        !_disposed &&
        !_intentionalDisconnect;
  }

  void _startStageATimeout(int attemptId) {
    if (!_isAttemptCurrent(attemptId)) return;
    _stageACandidateTimer?.cancel();
    _stageBConnectTimer?.cancel();
    _stageACandidateTimer = Timer(_stageACandidateTimeout, () {
      if (!_isAttemptCurrent(attemptId)) return;
      final attempt = _attempt;
      if (attempt == null) return;
      if (attempt.firstRemoteIceAt != null) {
        _startStageBTimeout(attemptId);
        return;
      }

      _logAttemptEvent(attemptId, 'timeout_stage_a');
      _updateState(
        MonitorConnectionState.failed,
        error: 'No remote ICE candidates within 3 seconds',
      );
      _scheduleRecovery(attemptId, reason: 'timeout_stage_a');
    });
  }

  void _startStageBTimeout(int attemptId) {
    if (!_isAttemptCurrent(attemptId)) return;
    final attempt = _attempt;
    if (attempt == null || attempt.stageBStarted) return;

    attempt.stageBStarted = true;
    _stageACandidateTimer?.cancel();
    _stageACandidateTimer = null;
    _stageBConnectTimer?.cancel();
    _stageBConnectTimer = Timer(_stageBConnectTimeout, () {
      if (!_isAttemptCurrent(attemptId)) return;
      if (_connectionInfo.state == MonitorConnectionState.connected) return;

      _logAttemptEvent(attemptId, 'timeout_stage_b');
      _updateState(
        MonitorConnectionState.failed,
        error: 'WebRTC did not connect within 8 seconds',
      );
      _scheduleRecovery(attemptId, reason: 'timeout_stage_b');
    });
  }

  void _cancelWebRtcAttemptTimers() {
    _stageACandidateTimer?.cancel();
    _stageACandidateTimer = null;
    _stageBConnectTimer?.cancel();
    _stageBConnectTimer = null;
  }

  void _deactivateCurrentAttempt() {
    _attempt?.isActive = false;
    _attempt = null;
    _cancelWebRtcAttemptTimers();
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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

  void _logAttemptEvent(
    int attemptId,
    String event, {
    Map<String, Object?>? details,
  }) {
    final attempt = _attempt;
    final startedAt = attempt != null && attempt.id == attemptId
        ? attempt.startedAt
        : null;
    final elapsedMs = startedAt == null
        ? -1
        : DateTime.now().difference(startedAt).inMilliseconds;

    final detailsText = details == null || details.isEmpty
        ? ''
        : ' ${details.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    debugPrint('[WebRTC][$attemptId][$elapsedMs ms] $event$detailsText');
  }

  String? _extractRemoteUfragFromSdp(String sdp) {
    for (final line in sdp.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('a=ice-ufrag:')) {
        final value = trimmed.substring('a=ice-ufrag:'.length).trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }

  String? _extractUfragFromCandidate(String candidate) {
    final tokens = candidate.split(RegExp(r'\s+'));
    for (var i = 0; i < tokens.length - 1; i++) {
      if (tokens[i] == 'ufrag') {
        final value = tokens[i + 1].trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }

  void _updateState(MonitorConnectionState state, {String? error}) {
    if (_disposed) return;
    if (state == MonitorConnectionState.connecting ||
        state == MonitorConnectionState.reconnecting) {
      _connectionInfo = _connectionInfo.copyWith(
        state: state,
        quality: ConnectionQuality.unknown,
        packetLossPercent: 0,
        errorMessage: error,
      );
    } else {
      _connectionInfo = _connectionInfo.copyWith(
        state: state,
        errorMessage: error,
      );
    }
    notifyListeners();
  }

  void _cancelSubscriptions() {
    _cancelWebRtcAttemptTimers();
    _signalRStateSub?.cancel();
    _signalRStateSub = null;
    _iceCandidateSub?.cancel();
    _iceCandidateSub = null;
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
        if (isConnected) {
          _notification.showForegroundNotification().catchError((e) {
            debugPrint('Failed to show foreground notification: $e');
          });
        }
        break;
      case AppLifecycleState.resumed:
        _isInBackground = false;
        _notification.cancelForegroundNotification();
        break;
      case AppLifecycleState.detached:
        _isInBackground = false;
        if (!_intentionalDisconnect) {
          _notification.cancelAll().catchError((e) {
            debugPrint('Failed to cancel notifications on detach: $e');
          });
        }
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _webRtcRetryInFlight = false;
    WidgetsBinding.instance.removeObserver(this);
    _cancelReconnectTimer();
    _deactivateCurrentAttempt();
    _cancelSubscriptions();
    _signalR.dispose();
    _webRtc.dispose();
    super.dispose();
  }
}
