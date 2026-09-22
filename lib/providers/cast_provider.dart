import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import '../models/cast_device.dart';
import 'connection_provider.dart';

final _log = Logger('CastProvider');

/// Cast devices and sessions, all of which live on the backend — the app only
/// picks targets and reads state back.
class CastProvider extends ChangeNotifier {
  final List<CastDevice> _devices = <CastDevice>[];
  final Map<int, List<String>> _roomTargets = <int, List<String>>{};

  ConnectionProvider? _connection;
  StreamSubscription<void>? _castStateSub;
  bool _isLoading = false;
  bool _isScanning = false;
  String? _lastError;

  List<CastDevice> get devices => List.unmodifiable(_devices);
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  String? get lastError => _lastError;

  List<CastDevice> get displays =>
      _devices.where((d) => d.isVideoCapable).toList(growable: false);

  List<CastDevice> get speakers =>
      _devices.where((d) => !d.isVideoCapable).toList(growable: false);

  /// Devices currently playing the given room.
  List<CastDevice> devicesCastingRoom(int roomId) =>
      _devices.where((d) => d.castingRoomId == roomId).toList(growable: false);

  bool isRoomCasting(int roomId) =>
      _devices.any((d) => d.castingRoomId == roomId);

  /// Saved default targets for a room, empty until [loadRoomTargets] has run.
  List<String> savedTargetsForRoom(int roomId) =>
      List.unmodifiable(_roomTargets[roomId] ?? const <String>[]);

  void bindConnection(ConnectionProvider connection) {
    if (identical(_connection, connection)) return;
    _connection = connection;

    _castStateSub?.cancel();
    _castStateSub = connection.signalR.onCastStateChanged.listen((_) {
      unawaited(refreshDevices());
    });

    if (connection.isConnected) {
      unawaited(refreshDevices());
    }
  }

  Future<void> refreshDevices() async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return;

    _isLoading = true;
    notifyListeners();
    try {
      final devices = await connection.signalR.getCastDevices();
      _devices
        ..clear()
        ..addAll(devices);
      _lastError = null;
    } catch (e, st) {
      _log.warning('Failed to load cast devices', e, st);
      _lastError = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Runs an mDNS sweep on the backend rather than waiting for the next one.
  Future<void> scanForDevices() async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return;

    _isScanning = true;
    notifyListeners();
    try {
      final devices = await connection.signalR.refreshCastDevices();
      _devices
        ..clear()
        ..addAll(devices);
      _lastError = null;
    } catch (e, st) {
      _log.warning('Cast scan failed', e, st);
      _lastError = e.toString();
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<bool> addDeviceByAddress({
    required String host,
    int port = 8009,
    String? name,
    bool isVideoCapable = false,
  }) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return false;

    try {
      await connection.signalR.addCastDevice(
        host: host,
        port: port,
        name: name,
        isVideoCapable: isVideoCapable,
      );
      _lastError = null;
      await refreshDevices();
      return true;
    } catch (e, st) {
      _log.warning('Failed to add cast device at $host', e, st);
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> forgetDevice(String deviceId) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return false;

    try {
      final removed = await connection.signalR.forgetCastDevice(deviceId);
      await refreshDevices();
      return removed;
    } catch (e, st) {
      _log.warning('Failed to forget cast device $deviceId', e, st);
      return false;
    }
  }

  Future<List<String>> loadRoomTargets(int roomId) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) {
      return savedTargetsForRoom(roomId);
    }

    try {
      final targets = await connection.signalR.getRoomCastTargets(roomId);
      _roomTargets[roomId] = targets;
      notifyListeners();
      return targets;
    } catch (e, st) {
      _log.warning('Failed to load cast targets for room $roomId', e, st);
      return savedTargetsForRoom(roomId);
    }
  }

  Future<void> saveRoomTargets(int roomId, List<String> deviceIds) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return;

    await connection.signalR.setRoomCastTargets(roomId, deviceIds);
    _roomTargets[roomId] = List<String>.from(deviceIds);
    notifyListeners();
  }

  /// Starts casting a room to [deviceIds]; an empty list uses the saved targets.
  Future<CastStartResult> startCast(int roomId, List<String> deviceIds) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) {
      return const CastStartResult();
    }

    try {
      final result = await connection.signalR.startCast(roomId, deviceIds);
      await refreshDevices();
      return result;
    } catch (e, st) {
      _log.warning('Failed to start cast for room $roomId', e, st);
      return CastStartResult(
        failed: {for (final id in deviceIds) id: e.toString()},
      );
    }
  }

  Future<void> stopCast(int roomId, {List<String> deviceIds = const []}) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return;

    try {
      await connection.signalR.stopCast(roomId, deviceIds);
    } catch (e, st) {
      _log.warning('Failed to stop cast for room $roomId', e, st);
    } finally {
      await refreshDevices();
    }
  }

  @override
  void dispose() {
    _castStateSub?.cancel();
    _castStateSub = null;
    super.dispose();
  }
}
