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
  bool _disposed = false;
  Timer? _reconnectTimer;
  Timer? _iceTimer;
  int _reconnectAttempts = 0;
  int _webRtcRetryAttempts = 0;
  bool _webRtcRetryInFlight = false;
  Future<void>? _disconnectInFlight;

  StreamSubscription? _signalRStateSub;
  StreamSubscription? _iceCandidateSub;
  StreamSubscription? _webRtcStateSub;
  StreamSubscription? _qualitySub;
  StreamSubscription? _audioLevelSub;
  StreamSubscription? _soundAlertSub;

  static const _iceTimeout = Duration(seconds: 15);
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

  Future<void> connect(String serverUrl) async {
    // Cancel existing subscriptions to prevent duplicates on reconnect
    _cancelSubscriptions();

    // Close any leftover peer connection from a previous attempt
    await _webRtc.close();

    _intentionalDisconnect = false;
    _reconnectAttempts = 0;
    _webRtcRetryAttempts = 0;
    _updateState(MonitorConnectionState.connecting);

    try {
      // Subscribe to SignalR state changes
      _signalRStateSub = _signalR.connectionState.listen(_onSignalRState);

      // Connect SignalR
      await _signalR.connect(serverUrl);

      // Subscribe to ICE candidates from server
      _iceCandidateSub = _signalR.onIceCandidate.listen((candidate) {
        _webRtc.addIceCandidate(
          candidate['candidate'] as String,
          candidate['sdpMid'] as String,
          candidate['sdpMLineIndex'] as int?,
        );
      });

      // Subscribe to WebRTC state BEFORE handshake so no transitions are missed
      _webRtcStateSub = _webRtc.connectionState.listen(_onWebRtcState);
      _qualitySub = _webRtc.packetLossStream.listen(_onPacketLoss);

      // Start WebRTC flow, passing ICE callback so it's set before createAnswer
      final sdpOffer = await _signalR.startWebRtcStream();
      final sdpAnswer = await _webRtc.handleOffer(
        sdpOffer,
        onIceCandidate: (candidate) {
          _signalR.addIceCandidate(
            candidate.candidate!,
            candidate.sdpMid!,
            candidate.sdpMLineIndex,
          );
        },
      );

      // Send answer
      await _signalR.setRemoteDescription('answer', sdpAnswer);

      // Re-subscribe to audio streams (needed after reconnect)
      _subscribeToAudioStreams();

      // Fetch audio settings
      try {
        final settings = await _signalR.getAudioSettings();
        _settingsProvider?.updateAudioSettings(settings);
      } catch (e) {
        debugPrint('Failed to fetch audio settings: $e');
      }

      // State stays 'connecting' until _onWebRtcState fires 'connected'
      // after ICE negotiation actually succeeds.

      // ICE negotiation timeout — if WebRTC doesn't reach 'connected'
      // within this window, treat it as a failed attempt.
      _iceTimer?.cancel();
      _iceTimer = Timer(_iceTimeout, () {
        if (_connectionInfo.state == MonitorConnectionState.connecting ||
            _connectionInfo.state == MonitorConnectionState.reconnecting) {
          debugPrint('ICE negotiation timed out after $_iceTimeout');
          _updateState(MonitorConnectionState.failed,
              error: 'ICE negotiation timed out');
          if (_signalR.isConnected &&
              _webRtcRetryAttempts < _maxWebRtcRetries) {
            _retryWebRtcOnly();
          } else {
            _scheduleReconnect();
          }
        }
      });
    } catch (e) {
      debugPrint('Connection error: $e');
      _updateState(MonitorConnectionState.failed,
          error: e.toString());
      _scheduleReconnect();
    }
  }

  Future<void> disconnect() {
    final inFlight = _disconnectInFlight;
    if (inFlight != null) return inFlight;

    final operation = _performDisconnect();
    _disconnectInFlight = operation;

    return operation.whenComplete(() {
      _disconnectInFlight = null;
    });
  }

  Future<void> _performDisconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _webRtcRetryInFlight = false;
    _cancelSubscriptions();

    try {
      await _signalR.stopWebRtcStream();
    } catch (e) {
      debugPrint('Disconnect: failed to stop WebRTC stream: $e');
    }

    try {
      await _webRtc.close();
    } catch (e) {
      debugPrint('Disconnect: failed to close WebRTC: $e');
    }

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
        _iceTimer?.cancel();
        _iceTimer = null;
        _updateState(MonitorConnectionState.connected);
        _reconnectAttempts = 0;
        _webRtcRetryAttempts = 0;
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _iceTimer?.cancel();
        _iceTimer = null;
        if (!_intentionalDisconnect) {
          if (_signalR.isConnected &&
              _webRtcRetryAttempts < _maxWebRtcRetries) {
            _retryWebRtcOnly();
          } else {
            _updateState(MonitorConnectionState.reconnecting);
            _scheduleReconnect();
          }
        }
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
    if (_intentionalDisconnect) return;
    _reconnectTimer?.cancel();
    _webRtcRetryAttempts = 0;

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
        try {
          await _signalR.stopWebRtcStream();
        } catch (e) {
          debugPrint('Reconnect: failed to stop server stream: $e');
        }
        await _webRtc.close();
        await _signalR.disconnect();
        _audioProvider?.reset();
        await connect(url);
      }
    });
  }

  Future<void> _retryWebRtcOnly() async {
    if (_webRtcRetryInFlight || _intentionalDisconnect || _disposed) return;
    _webRtcRetryInFlight = true;

    try {
      _webRtcRetryAttempts++;
      debugPrint(
          'WebRTC-only retry attempt $_webRtcRetryAttempts/$_maxWebRtcRetries');

      _updateState(MonitorConnectionState.reconnecting);

      // Cancel ICE timer and WebRTC-specific subscriptions only.
      // Keep _signalRStateSub and _iceCandidateSub alive.
      _iceTimer?.cancel();
      _iceTimer = null;
      _webRtcStateSub?.cancel();
      _webRtcStateSub = null;
      _qualitySub?.cancel();
      _qualitySub = null;

      // Tell server to stop current stream
      try {
        await _signalR.stopWebRtcStream();
      } catch (e) {
        debugPrint('WebRTC retry: failed to stop server stream: $e');
      }

      // Close local peer connection
      await _webRtc.close();

      // Brief delay for server-side cleanup
      await Future.delayed(_webRtcRetryDelay);

      // Bail out if state changed during the delay
      if (_intentionalDisconnect || _disposed) return;

      // If SignalR dropped, fall back to full reconnect
      if (!_signalR.isConnected) {
        debugPrint(
            'WebRTC retry: SignalR disconnected, falling back to full reconnect');
        _scheduleReconnect();
        return;
      }

      // Re-subscribe to WebRTC state before handshake
      _webRtcStateSub = _webRtc.connectionState.listen(_onWebRtcState);
      _qualitySub = _webRtc.packetLossStream.listen(_onPacketLoss);

      // Request new SDP offer via existing SignalR connection
      final sdpOffer = await _signalR.startWebRtcStream();
      final sdpAnswer = await _webRtc.handleOffer(
        sdpOffer,
        onIceCandidate: (candidate) {
          _signalR.addIceCandidate(
            candidate.candidate!,
            candidate.sdpMid!,
            candidate.sdpMLineIndex,
          );
        },
      );

      // Send answer back to server
      await _signalR.setRemoteDescription('answer', sdpAnswer);

      // Re-subscribe to audio streams
      _subscribeToAudioStreams();

      // Start ICE timeout
      _iceTimer?.cancel();
      _iceTimer = Timer(_iceTimeout, () {
        if (_connectionInfo.state == MonitorConnectionState.connecting ||
            _connectionInfo.state == MonitorConnectionState.reconnecting) {
          debugPrint('ICE negotiation timed out during WebRTC retry');
          // Will trigger _onWebRtcState which routes to retry or full reconnect
        }
      });
    } catch (e) {
      debugPrint('WebRTC retry error: $e');
      if (!_intentionalDisconnect && !_disposed) {
        if (_webRtcRetryAttempts < _maxWebRtcRetries &&
            _signalR.isConnected) {
          _reconnectTimer?.cancel();
          _reconnectTimer = Timer(_webRtcRetryDelay, () {
            _webRtcRetryInFlight = false;
            _retryWebRtcOnly();
          });
          return;
        } else {
          _scheduleReconnect();
        }
      }
    } finally {
      _webRtcRetryInFlight = false;
    }
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
    _iceTimer?.cancel();
    _iceTimer = null;
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
    _reconnectTimer?.cancel();
    _iceTimer?.cancel();
    _cancelSubscriptions();
    _signalR.dispose();
    _webRtc.dispose();
    super.dispose();
  }
}
