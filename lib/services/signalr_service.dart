import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:signalr_netcore/signalr_client.dart';
import '../models/audio_settings.dart';

class SignalRService {
  HubConnection? _connection;
  bool _disposed = false;
  StreamSubscription<LogRecord>? _logSubscription;

  final _connectionStateController =
      StreamController<HubConnectionState>.broadcast();
  final _iceCandidateController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<HubConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<Map<String, dynamic>> get onIceCandidate =>
      _iceCandidateController.stream;

  bool get isConnected =>
      _connection?.state == HubConnectionState.Connected;

  Future<void> connect(String serverUrl) async {
    await disconnect();

    final hubUrl = serverUrl.endsWith('/')
        ? '${serverUrl}audioHub'
        : '$serverUrl/audioHub';

    final logger = Logger('SignalR');
    _logSubscription?.cancel();
    _logSubscription = logger.onRecord.listen(
      (record) => debugPrint('[SignalR] ${record.level.name}: ${record.message}'),
    );

    _connection = HubConnectionBuilder()
        .withUrl(
          hubUrl,
          options: HttpConnectionOptions(
            // transport: HttpTransportType.LongPolling,
            logger: logger,
            logMessageContent: true,
            requestTimeout: 10000,
          ),
        )
        .configureLogging(logger)
        .withAutomaticReconnect()
        .build();

    _connection!.onclose(({error}) {
      if (!_disposed) {
        _connectionStateController.add(HubConnectionState.Disconnected);
      }
    });

    _connection!.onreconnecting(({error}) {
      if (!_disposed) {
        _connectionStateController.add(HubConnectionState.Reconnecting);
      }
    });

    _connection!.onreconnected(({connectionId}) {
      if (!_disposed) {
        _connectionStateController.add(HubConnectionState.Connected);
      }
    });

    _connection!.on('ReceiveIceCandidate', (arguments) {
      if (arguments != null && arguments.length >= 3) {
        _iceCandidateController.add({
          'candidate': arguments[0] as String,
          'sdpMid': arguments[1] as String,
          'sdpMLineIndex': arguments[2] as int?,
        });
      }
    });

    try {
      await _connection!.start();
      _connectionStateController.add(HubConnectionState.Connected);
    } catch (e) {
      _connectionStateController.add(HubConnectionState.Disconnected);
      rethrow;
    }
  }

  Future<String> startWebRtcStream() async {
    _ensureConnected();
    final result = await _connection!.invoke('StartWebRtcStream');
    return result as String;
  }

  Future<void> setRemoteDescription(String type, String sdp) async {
    _ensureConnected();
    await _connection!
        .invoke('SetRemoteDescription', args: [type, sdp]);
  }

  Future<void> addIceCandidate(
      String candidate, String sdpMid, int? sdpMLineIndex) async {
    _ensureConnected();
    final List<Object> args = [candidate, sdpMid];
    if (sdpMLineIndex != null) {
      args.add(sdpMLineIndex);
    }
    await _connection!.invoke('AddIceCandidate', args: args);
  }

  Future<void> stopWebRtcStream() async {
    if (!isConnected) return;
    try {
      await _connection!.invoke('StopWebRtcStream');
    } catch (e) {
      debugPrint('Error stopping WebRTC stream: $e');
    }
  }

  Future<AudioSettings> getAudioSettings() async {
    _ensureConnected();
    final result = await _connection!.invoke('GetAudioSettings');
    if (result is Map<String, dynamic>) {
      return AudioSettings.fromJson(result);
    }
    return const AudioSettings();
  }

  Future<void> updateAudioSettings(AudioSettings settings) async {
    _ensureConnected();
    await _connection!
        .invoke('UpdateAudioSettings', args: [settings.toJson()]);
  }

  Future<void> disconnect() async {
    try {
      await _connection?.stop();
    } catch (e) {
      debugPrint('Error disconnecting SignalR: $e');
    }
    _connection = null;
    _logSubscription?.cancel();
    _logSubscription = null;
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _logSubscription?.cancel();
    _logSubscription = null;
    _connectionStateController.close();
    _iceCandidateController.close();
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw StateError('SignalR is not connected');
    }
  }
}
