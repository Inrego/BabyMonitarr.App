import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/global_settings.dart';
import '../models/room.dart';
import 'connection_provider.dart';

class RoomProvider extends ChangeNotifier {
  final List<Room> _rooms = <Room>[];
  GlobalSettings _globalSettings = const GlobalSettings();
  int? _editingRoomId;
  bool _isLoading = false;
  bool _isLoaded = false;

  ConnectionProvider? _connection;
  StreamSubscription? _roomsUpdatedSub;
  StreamSubscription? _activeRoomChangedSub;
  StreamSubscription? _settingsUpdatedSub;

  List<Room> get rooms => List.unmodifiable(_rooms);
  GlobalSettings get globalSettings => _globalSettings;
  bool get isLoading => _isLoading;
  bool get isLoaded => _isLoaded;
  int? get editingRoomId => _editingRoomId;

  Room? get editingRoom =>
      _editingRoomId == null ? null : roomById(_editingRoomId!);

  Room? get activeRoom {
    for (final room in _rooms) {
      if (room.isActive) return room;
    }
    return null;
  }

  Room? roomById(int id) {
    for (final room in _rooms) {
      if (room.id == id) return room;
    }
    return null;
  }

  void bindConnection(ConnectionProvider connection) {
    if (identical(_connection, connection)) return;
    _connection = connection;
    _resetSubscriptions();

    _roomsUpdatedSub = connection.signalR.onRoomsUpdated.listen((_) {
      unawaited(refreshRooms());
    });

    _activeRoomChangedSub = connection.signalR.onActiveRoomChanged.listen((
      room,
    ) {
      _setActiveRoom(room.id);
    });

    _settingsUpdatedSub = connection.signalR.onSettingsUpdated.listen((_) {
      unawaited(refreshGlobalSettings());
    });

    if (connection.isConnected) {
      unawaited(refreshAll());
    }
  }

  Future<void> refreshAll() async {
    await Future.wait([refreshRooms(), refreshGlobalSettings()]);
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> refreshRooms() async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return;

    _isLoading = true;
    notifyListeners();
    try {
      final rooms = await connection.signalR.getRooms();
      _rooms
        ..clear()
        ..addAll(rooms);

      if (_editingRoomId != null && roomById(_editingRoomId!) == null) {
        _editingRoomId = null;
      }
      _isLoaded = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshGlobalSettings() async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return;

    final settings = await connection.signalR.getGlobalSettings();
    _globalSettings = settings;
    notifyListeners();
  }

  Future<Room?> createRoom() async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return null;
    final created = await connection.signalR.createRoom(
      const Room(
        name: 'New Monitor',
        icon: 'baby',
        monitorType: 'camera_audio',
      ),
    );
    await refreshRooms();
    _editingRoomId = created.id;
    notifyListeners();
    return created;
  }

  Future<Room?> updateRoom(Room room) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return null;
    final updated = await connection.signalR.updateRoom(room);
    await refreshRooms();
    return updated;
  }

  Future<bool> deleteRoom(int roomId) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return false;
    final deleted = await connection.signalR.deleteRoom(roomId);
    if (!deleted) return false;
    if (_editingRoomId == roomId) {
      _editingRoomId = null;
    }
    await refreshRooms();
    return true;
  }

  Future<Room?> selectRoomForMonitoring(int roomId) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return null;
    final room = await connection.signalR.selectRoom(roomId);
    if (room != null) {
      _setActiveRoom(room.id);
    }
    return room;
  }

  Future<void> saveRoomAndGlobalSettings(
    Room room,
    GlobalSettings globalSettings,
  ) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return;

    await Future.wait([
      connection.signalR.updateRoom(room),
      connection.signalR.updateGlobalSettings(globalSettings),
    ]);
    _globalSettings = globalSettings;
    await refreshRooms();
  }

  void setEditingRoomId(int? roomId) {
    if (_editingRoomId == roomId) return;
    _editingRoomId = roomId;
    notifyListeners();
  }

  void _setActiveRoom(int activeRoomId) {
    var changed = false;
    final updated = <Room>[];
    for (final room in _rooms) {
      final next = room.copyWith(isActive: room.id == activeRoomId);
      if (next.isActive != room.isActive) {
        changed = true;
      }
      updated.add(next);
    }
    if (!changed) return;
    _rooms
      ..clear()
      ..addAll(updated);
    notifyListeners();
  }

  void _resetSubscriptions() {
    _roomsUpdatedSub?.cancel();
    _roomsUpdatedSub = null;
    _activeRoomChangedSub?.cancel();
    _activeRoomChangedSub = null;
    _settingsUpdatedSub?.cancel();
    _settingsUpdatedSub = null;
  }

  @override
  void dispose() {
    _resetSubscriptions();
    super.dispose();
  }
}
