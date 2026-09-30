import 'dart:async';
import 'package:logging/logging.dart';
import 'package:signalr_netcore/signalr_client.dart';
// Not re-exported by signalr_client.dart, so it needs its own import.
import 'package:signalr_netcore/iretry_policy.dart';
import '../models/audio_settings.dart';
import '../models/cast_device.dart';
import '../models/global_settings.dart';
import '../models/nest_device.dart';
import '../models/remote_ice_candidate.dart';
import '../models/remote_video_ice_candidate.dart';
import '../models/room.dart';
import '../models/talkback_status.dart';
import '../models/webrtc_client_config.dart';
import 'talkback_hub.dart';

final _log = Logger('SignalRService');

/// Disables signalr_netcore's built-in reconnect loop.
///
/// Returning null on the first attempt makes HubConnection._reconnect() call
/// _completeClose() immediately, so `onclose` fires and ConnectionProvider's
/// reconnect loop is the single driver. See the note in [SignalRService.connect].
class NeverRetryPolicy implements IRetryPolicy {
  const NeverRetryPolicy();

  @override
  int? nextRetryDelayInMilliseconds(RetryContext retryContext) => null;
}

class SignalRService implements TalkbackHub {
  static const int _defaultKeepAliveMs = 10000;
  static const int _defaultServerTimeoutMs = 35000;
  // Sits above the 10s HTTP requestTimeout and below the 35s server timeout so
  // hung hub invokes can't deadlock the serialized recovery queue overnight.
  static const Duration _invokeTimeout = Duration(seconds: 12);

  HubConnection? _connection;
  WebRtcClientConfig? _cachedWebRtcConfig;
  bool _disposed = false;

  final _connectionStateController =
      StreamController<HubConnectionState>.broadcast();
  final _iceCandidateController =
      StreamController<RemoteIceCandidate>.broadcast();
  final _videoIceCandidateController =
      StreamController<RemoteVideoIceCandidate>.broadcast();
  final _roomsUpdatedController = StreamController<void>.broadcast();
  final _activeRoomChangedController = StreamController<Room>.broadcast();
  final _settingsUpdatedController = StreamController<void>.broadcast();
  final _castStateChangedController = StreamController<void>.broadcast();
  final _talkbackStatusController =
      StreamController<TalkbackStatus>.broadcast();
  final _talkbackIceCandidateController =
      StreamController<RemoteIceCandidate>.broadcast();

  @override
  Stream<HubConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<RemoteIceCandidate> get onIceCandidate =>
      _iceCandidateController.stream;
  Stream<RemoteVideoIceCandidate> get onVideoIceCandidate =>
      _videoIceCandidateController.stream;
  Stream<void> get onRoomsUpdated => _roomsUpdatedController.stream;
  Stream<Room> get onActiveRoomChanged => _activeRoomChangedController.stream;
  Stream<void> get onSettingsUpdated => _settingsUpdatedController.stream;
  Stream<void> get onCastStateChanged => _castStateChangedController.stream;
  @override
  Stream<TalkbackStatus> get onTalkbackStatusChanged =>
      _talkbackStatusController.stream;
  @override
  Stream<RemoteIceCandidate> get onTalkbackIceCandidate =>
      _talkbackIceCandidateController.stream;

  @override
  bool get isConnected => _connection?.state == HubConnectionState.Connected;

  Future<void> connect(String serverUrl, {String? apiKey}) async {
    await disconnect();
    final hubUrl = _normalizeHubUrl(serverUrl);

    final logger = Logger('SignalR');

    // We intentionally do NOT let signalr_netcore drive reconnection: its
    // policy silently stops retrying after a TimeoutException during
    // negotiation (observed in production at 2026-05-19), leaving the library
    // in a permanent Reconnecting/zombie state with no `onclose` callback.
    // Reconnect is driven from ConnectionProvider._ensureSignalRReconnectLoop()
    // with our own infinite backoff via SignalRService.reconnectDelayForAttempt.
    //
    // Opting out requires an explicit never-retry policy, NOT just omitting
    // `.withAutomaticReconnect(...)`. In signalr_netcore 1.4.4 the HubConnection
    // constructor does `_reconnectPolicy = reconnectPolicy ?? DefaultRetryPolicy()`
    // (hub_connection.dart:162), so omitting the builder call leaves automatic
    // reconnect fully ON. Both loops then raced on every drop: the library's
    // `_reconnect()` started a negotiation, our loop called disconnect() on top
    // of it, and the result was `Failed to start the connection: The connection
    // was stopped during negotiation` followed by a stop() that wedged until
    // the 5s bail-out — 17 times in the 2026-09-22 overnight log.
    final connection = HubConnectionBuilder()
        .withUrl(
          hubUrl,
          options: HttpConnectionOptions(
            logger: logger,
            logMessageContent: true,
            requestTimeout: 10000,
            accessTokenFactory: apiKey != null && apiKey.isNotEmpty
                ? () async => apiKey
                : null,
          ),
        )
        .withAutomaticReconnect(reconnectPolicy: const NeverRetryPolicy())
        .configureLogging(logger)
        .build();
    _connection = connection;

    connection
      ..keepAliveIntervalInMilliseconds = _defaultKeepAliveMs
      ..serverTimeoutInMilliseconds = _defaultServerTimeoutMs;

    // Identity guard on every callback: a torn-down HubConnection can still
    // fire events after a fresh one has been built (codex flagged this race).
    // `identical(_connection, connection)` ensures only the current connection
    // can push to the shared streams.
    bool isCurrent() => identical(_connection, connection);

    connection.onclose(({error}) {
      if (_disposed || !isCurrent()) return;
      _connectionStateController.add(HubConnectionState.Disconnected);
    });

    // Kept for safety though no path emits Reconnecting under
    // NeverRetryPolicy: _reconnect() bails before setting that state. If a
    // future change reintroduces retries, the state still reaches
    // ConnectionProvider.
    connection.onreconnecting(({error}) {
      if (_disposed || !isCurrent()) return;
      _connectionStateController.add(HubConnectionState.Reconnecting);
    });

    connection.onreconnected(({connectionId}) {
      if (_disposed || !isCurrent()) return;
      _connectionStateController.add(HubConnectionState.Connected);
    });

    connection.on('ReceiveAudioIceCandidate', (arguments) {
      if (!isCurrent()) return;
      final parsed = tryParseIceCandidateArgs(
        arguments is List ? arguments : null,
      );
      if (parsed == null) {
        _log.warning('Ignoring malformed ReceiveAudioIceCandidate payload');
        return;
      }
      _iceCandidateController.add(parsed);
    });

    connection.on('ReceiveVideoIceCandidate', (arguments) {
      if (!isCurrent()) return;
      final parsed = tryParseVideoIceCandidateArgs(
        arguments is List ? arguments : null,
      );
      if (parsed == null) {
        _log.warning('Ignoring malformed ReceiveVideoIceCandidate payload');
        return;
      }
      _videoIceCandidateController.add(parsed);
    });

    connection.on('RoomsUpdated', (_) {
      if (!isCurrent()) return;
      _roomsUpdatedController.add(null);
    });

    connection.on('ActiveRoomChanged', (arguments) {
      if (!isCurrent()) return;
      if (arguments is! List || arguments.isEmpty) return;
      final raw = arguments.first;
      final roomMap = _asJsonMap(raw);
      if (roomMap == null) return;
      _activeRoomChangedController.add(Room.fromJson(roomMap));
    });

    connection.on('SettingsUpdated', (_) {
      if (!isCurrent()) return;
      _settingsUpdatedController.add(null);
    });

    connection.on('CastStateChanged', (_) {
      if (!isCurrent()) return;
      _castStateChangedController.add(null);
    });

    connection.on('TalkbackStatusChanged', (arguments) {
      if (!isCurrent()) return;
      final status = tryParseTalkbackStatusArgs(
        arguments is List ? arguments : null,
      );
      if (status == null) {
        _log.warning('Ignoring malformed TalkbackStatusChanged payload');
        return;
      }
      _talkbackStatusController.add(status);
    });

    connection.on('ReceiveTalkbackIceCandidate', (arguments) {
      if (!isCurrent()) return;
      final parsed = tryParseIceCandidateArgs(
        arguments is List ? arguments : null,
      );
      if (parsed == null) {
        _log.warning('Ignoring malformed ReceiveTalkbackIceCandidate payload');
        return;
      }
      _talkbackIceCandidateController.add(parsed);
    });

    try {
      await connection.start();
      if (!isCurrent()) return;
      _cachedWebRtcConfig = null;
      _connectionStateController.add(HubConnectionState.Connected);
    } catch (e) {
      if (isCurrent()) {
        // Null the field so a later-completing abandoned start() can't
        // resurface as Connected on a stale HubConnection, and so the next
        // connect() rebuilds cleanly without trying to stop() a half-built
        // connection.
        _connection = null;
        _connectionStateController.add(HubConnectionState.Disconnected);
      }
      rethrow;
    }
  }

  Future<String> startAudioStream(int roomId) async {
    final result = await _invoke('StartAudioStream', args: [roomId]);
    return result as String;
  }

  Future<void> setAudioRemoteDescription(
    int roomId,
    String type,
    String sdp,
  ) async {
    await _invoke('SetAudioRemoteDescription', args: [roomId, type, sdp]);
  }

  Future<void> addAudioIceCandidate(
    int roomId,
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) async {
    final List<Object> args = [
      roomId,
      candidate,
      sdpMid ?? '',
      sdpMLineIndex ?? 0,
    ];
    await _invoke('AddAudioIceCandidate', args: args);
  }

  Future<void> stopAudioStream(int roomId) async {
    if (!isConnected) return;
    try {
      await _invoke('StopAudioStream', args: [roomId]);
    } catch (e, st) {
      _log.warning('Error stopping audio stream for room $roomId', e, st);
    }
  }

  Future<String> startVideoStream(int roomId) async {
    final result = await _invoke('StartVideoStream', args: [roomId]);
    return result as String;
  }

  Future<void> setVideoRemoteDescription(
    int roomId,
    String type,
    String sdp,
  ) async {
    await _invoke('SetVideoRemoteDescription', args: [roomId, type, sdp]);
  }

  Future<void> addVideoIceCandidate(
    int roomId,
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) async {
    final args = <Object>[roomId, candidate, sdpMid ?? '', sdpMLineIndex ?? 0];
    await _invoke('AddVideoIceCandidate', args: args);
  }

  Future<void> stopVideoStream(int roomId) async {
    if (!isConnected) return;
    try {
      await _invoke('StopVideoStream', args: [roomId]);
    } catch (e, st) {
      _log.warning('Error stopping video stream for room $roomId', e, st);
    }
  }

  @override
  Future<TalkbackStatus> getTalkbackStatus(int roomId) async {
    final result = await _invoke('GetTalkbackStatus', args: [roomId]);
    final map = _asJsonMap(result);
    return map == null
        ? TalkbackStatus(roomId: roomId)
        : TalkbackStatus.fromJson(map);
  }

  @override
  Future<String> startTalkbackUplink(int roomId) async {
    final result = await _invoke('StartTalkbackUplink', args: [roomId]);
    return result as String;
  }

  @override
  Future<void> setTalkbackRemoteDescription(
    int roomId,
    String type,
    String sdp,
  ) async {
    await _invoke('SetTalkbackRemoteDescription', args: [roomId, type, sdp]);
  }

  @override
  Future<void> addTalkbackIceCandidate(
    int roomId,
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) async {
    final args = <Object>[roomId, candidate, sdpMid ?? '', sdpMLineIndex ?? 0];
    await _invoke('AddTalkbackIceCandidate', args: args);
  }

  @override
  Future<void> stopTalkbackUplink(int roomId) async {
    if (!isConnected) return;
    await _invoke('StopTalkbackUplink', args: [roomId]);
  }

  @override
  Future<TalkbackStartResult> startTalkback(int roomId) async {
    final result = await _invoke('StartTalkback', args: [roomId]);
    final map = _asJsonMap(result);
    return map == null
        ? const TalkbackStartResult(success: false)
        : TalkbackStartResult.fromJson(map);
  }

  @override
  Future<void> stopTalkback(int roomId) async {
    if (!isConnected) return;
    await _invoke('StopTalkback', args: [roomId]);
  }

  @override
  Future<void> setTalkbackVolume(int roomId, double volume) async {
    await _invoke(
      'SetTalkbackVolume',
      args: [roomId, TalkbackStatus.clampVolume(volume)],
    );
  }

  Future<AudioSettings> getAudioSettings() async {
    final result = await _invoke('GetAudioSettings');
    final map = _asJsonMap(result);
    return map == null ? const AudioSettings() : AudioSettings.fromJson(map);
  }

  Future<GlobalSettings> getGlobalSettings() async {
    final result = await _invoke('GetGlobalSettings');
    final map = _asJsonMap(result);
    return map == null ? const GlobalSettings() : GlobalSettings.fromJson(map);
  }

  @override
  Future<WebRtcClientConfig> getWebRtcConfig() async {
    if (_cachedWebRtcConfig != null) {
      return _cachedWebRtcConfig!;
    }

    try {
      final result = await _invoke('GetWebRtcConfig');
      final map = _asJsonMap(result);
      final config = map == null
          ? WebRtcClientConfig.fallback()
          : WebRtcClientConfig.fromJson(map);
      _cachedWebRtcConfig = config;
      return config;
    } catch (_) {
      final fallback = WebRtcClientConfig.fallback();
      _cachedWebRtcConfig = fallback;
      return fallback;
    }
  }

  Future<List<NestDevice>> getNestDevices() async {
    final result = await _invoke('GetNestDevices');
    if (result is! List) return const [];
    return result
        .map((raw) => _asJsonMap(raw))
        .whereType<Map<String, dynamic>>()
        .map(NestDevice.fromJson)
        .toList(growable: false);
  }

  Future<bool> isNestLinked() async {
    final result = await _invoke('IsNestLinked');
    if (result is bool) return result;
    if (result is String) {
      return result.toLowerCase() == 'true';
    }
    return false;
  }

  Future<void> updateGlobalSettings(GlobalSettings settings) async {
    await _invoke('UpdateAudioSettings', args: [settings.toJson()]);
  }

  Future<void> updateAudioSettings(AudioSettings settings) async {
    await _invoke('UpdateAudioSettings', args: [settings.toJson()]);
  }

  Future<List<Room>> getRooms() async {
    final result = await _invoke('GetRooms');
    if (result is! List) return const [];
    return result
        .map((raw) => _asJsonMap(raw))
        .whereType<Map<String, dynamic>>()
        .map(Room.fromJson)
        .toList(growable: false);
  }

  Future<Room> createRoom(Room room) async {
    final result = await _invoke('CreateRoom', args: [room.toJson()]);
    final map = _asJsonMap(result);
    return map == null ? room : Room.fromJson(map);
  }

  Future<Room?> updateRoom(Room room) async {
    final result = await _invoke('UpdateRoom', args: [room.toJson()]);
    final map = _asJsonMap(result);
    return map == null ? null : Room.fromJson(map);
  }

  Future<bool> deleteRoom(int id) async {
    final result = await _invoke('DeleteRoom', args: [id]);
    return result == true;
  }

  Future<Room?> selectRoom(int roomId) async {
    final result = await _invoke('SelectRoom', args: [roomId]);
    final map = _asJsonMap(result);
    return map == null ? null : Room.fromJson(map);
  }

  Future<Room?> getActiveRoom() async {
    final result = await _invoke('GetActiveRoom');
    final map = _asJsonMap(result);
    return map == null ? null : Room.fromJson(map);
  }

  Future<List<CastDevice>> getCastDevices() async {
    final result = await _invoke('GetCastDevices');
    return _parseCastDevices(result);
  }

  Future<List<CastDevice>> refreshCastDevices() async {
    final result = await _invoke('RefreshCastDevices');
    return _parseCastDevices(result);
  }

  Future<CastDevice?> addCastDevice({
    required String host,
    int port = 8009,
    String? name,
    bool isVideoCapable = false,
  }) async {
    final result = await _invoke(
      'AddCastDevice',
      args: [host, port, name ?? '', isVideoCapable],
    );
    final map = _asJsonMap(result);
    return map == null ? null : CastDevice.fromJson(map);
  }

  Future<bool> forgetCastDevice(String deviceId) async {
    final result = await _invoke('ForgetCastDevice', args: [deviceId]);
    return result == true;
  }

  Future<List<String>> getRoomCastTargets(int roomId) async {
    final result = await _invoke('GetRoomCastTargets', args: [roomId]);
    if (result is! List) return const [];
    return result.map((raw) => raw.toString()).toList(growable: false);
  }

  Future<void> setRoomCastTargets(int roomId, List<String> deviceIds) async {
    await _invoke('SetRoomCastTargets', args: [roomId, deviceIds]);
  }

  Future<CastStartResult> startCast(int roomId, List<String> deviceIds) async {
    final result = await _invoke('StartCast', args: [roomId, deviceIds]);
    final map = _asJsonMap(result);
    return map == null
        ? const CastStartResult()
        : CastStartResult.fromJson(map);
  }

  Future<int> stopCast(int roomId, List<String> deviceIds) async {
    final result = await _invoke('StopCast', args: [roomId, deviceIds]);
    if (result is int) return result;
    if (result is num) return result.toInt();
    return 0;
  }

  Future<List<CastSession>> getCastSessions() async {
    final result = await _invoke('GetCastSessions');
    if (result is! List) return const [];
    return result
        .map((raw) => _asJsonMap(raw))
        .whereType<Map<String, dynamic>>()
        .map(CastSession.fromJson)
        .toList(growable: false);
  }

  static List<CastDevice> _parseCastDevices(Object? result) {
    if (result is! List) return const [];
    return result
        .map((raw) => _asJsonMap(raw))
        .whereType<Map<String, dynamic>>()
        .map(CastDevice.fromJson)
        .toList(growable: false);
  }

  Future<Object?> _invoke(String method, {List<Object>? args}) {
    _ensureConnected();
    return _connection!
        .invoke(method, args: args)
        .timeout(
          _invokeTimeout,
          onTimeout: () => throw TimeoutException(
            'SignalR invoke "$method" timed out after '
            '${_invokeTimeout.inSeconds}s',
            _invokeTimeout,
          ),
        );
  }

  Future<void> disconnect() async {
    // Null the field BEFORE awaiting stop(): signalr_netcore's stop() can wedge
    // on a zombie HubConnection (it awaits internal startPromise/transport
    // shutdown which never resolve after the library's retry-exhaustion path).
    // Bounded by a 5s timeout so a hung stop can't poison the serialized
    // operation queue in ConnectionProvider — the next connect() will rebuild
    // the connection from scratch.
    final connection = _connection;
    _connection = null;
    _cachedWebRtcConfig = null;
    if (connection == null) return;
    try {
      await connection.stop().timeout(const Duration(seconds: 5));
    } on TimeoutException catch (e, st) {
      _log.warning(
        'SignalR stop() did not return within 5s — abandoning connection',
        e,
        st,
      );
    } catch (e, st) {
      _log.warning('Error disconnecting SignalR', e, st);
    }
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _connectionStateController.close();
    _iceCandidateController.close();
    _videoIceCandidateController.close();
    _roomsUpdatedController.close();
    _activeRoomChangedController.close();
    _settingsUpdatedController.close();
    _castStateChangedController.close();
    _talkbackStatusController.close();
    _talkbackIceCandidateController.close();
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw StateError('SignalR is not connected');
    }
  }

  String _normalizeHubUrl(String serverUrl) {
    final base = normalizeServerUrl(serverUrl);
    return '$base/audioHub';
  }

  static String normalizeServerUrl(String serverUrl) {
    var normalized = serverUrl.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.toLowerCase().endsWith('/audiohub')) {
      normalized = normalized.substring(
        0,
        normalized.length - '/audioHub'.length,
      );
    }
    return normalized;
  }

  static RemoteIceCandidate? tryParseIceCandidateArgs(List? arguments) {
    if (arguments == null || arguments.length < 2) {
      return null;
    }

    final roomId = _parseInt(arguments[0]);
    if (roomId == null) return null;

    final rawCandidate = arguments[1];
    if (rawCandidate is! String || rawCandidate.trim().isEmpty) {
      return null;
    }

    final rawSdpMid = arguments.length > 2 ? arguments[2] : null;
    final rawSdpMLineIndex = arguments.length > 3 ? arguments[3] : null;

    String? sdpMid;
    if (rawSdpMid is String && rawSdpMid.trim().isNotEmpty) {
      sdpMid = rawSdpMid;
    } else if (rawSdpMid != null) {
      sdpMid = rawSdpMid.toString();
    }

    int? sdpMLineIndex;
    if (rawSdpMLineIndex is int) {
      sdpMLineIndex = rawSdpMLineIndex;
    } else if (rawSdpMLineIndex is num) {
      sdpMLineIndex = rawSdpMLineIndex.toInt();
    } else if (rawSdpMLineIndex is String) {
      sdpMLineIndex = int.tryParse(rawSdpMLineIndex);
    }

    return RemoteIceCandidate(
      roomId: roomId,
      candidate: rawCandidate,
      sdpMid: sdpMid,
      sdpMLineIndex: sdpMLineIndex,
    );
  }

  static RemoteVideoIceCandidate? tryParseVideoIceCandidateArgs(
    List? arguments,
  ) {
    if (arguments == null || arguments.length < 2) {
      return null;
    }

    final rawRoomId = arguments[0];
    final rawCandidate = arguments[1];
    if (rawCandidate is! String || rawCandidate.trim().isEmpty) {
      return null;
    }

    final roomId = _parseInt(rawRoomId);
    if (roomId == null) return null;

    final rawSdpMid = arguments.length > 2 ? arguments[2] : null;
    final rawSdpMLineIndex = arguments.length > 3 ? arguments[3] : null;

    String? sdpMid;
    if (rawSdpMid is String && rawSdpMid.trim().isNotEmpty) {
      sdpMid = rawSdpMid;
    } else if (rawSdpMid != null) {
      sdpMid = rawSdpMid.toString();
    }

    final sdpMLineIndex = _parseInt(rawSdpMLineIndex);

    return RemoteVideoIceCandidate(
      roomId: roomId,
      candidate: rawCandidate,
      sdpMid: sdpMid,
      sdpMLineIndex: sdpMLineIndex,
    );
  }

  static TalkbackStatus? tryParseTalkbackStatusArgs(List? arguments) {
    if (arguments == null || arguments.isEmpty) return null;
    final map = _asJsonMap(arguments.first);
    if (map == null || _parseInt(map['roomId']) == null) return null;
    return TalkbackStatus.fromJson(map);
  }

  static int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Map<String, dynamic>? _asJsonMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static int reconnectDelayForAttempt(int previousRetryCount) {
    if (previousRetryCount <= 0) return 0;
    if (previousRetryCount == 1) return 2000;
    if (previousRetryCount == 2) return 5000;
    if (previousRetryCount == 3) return 10000;
    if (previousRetryCount == 4) return 15000;
    return 15000;
  }
}
