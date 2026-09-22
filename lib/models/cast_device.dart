/// A Google Cast receiver the backend knows about.
class CastDevice {
  final String deviceId;
  final String name;
  final String model;
  final String host;

  /// True for TVs, Chromecasts and Nest Hubs; false for speakers.
  final bool isVideoCapable;
  final bool isGroup;
  final bool manuallyAdded;
  final bool isOnline;
  final DateTime? lastSeenUtc;

  /// Room currently cast to this device, or null when it is idle.
  final int? castingRoomId;
  final String? lastError;

  const CastDevice({
    required this.deviceId,
    this.name = '',
    this.model = '',
    this.host = '',
    this.isVideoCapable = false,
    this.isGroup = false,
    this.manuallyAdded = false,
    this.isOnline = false,
    this.lastSeenUtc,
    this.castingRoomId,
    this.lastError,
  });

  bool get isCasting => castingRoomId != null;

  factory CastDevice.fromJson(Map<String, dynamic> json) {
    return CastDevice(
      deviceId: (json['deviceId'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      model: (json['model'] as String?) ?? '',
      host: (json['host'] as String?) ?? '',
      isVideoCapable: json['isVideoCapable'] as bool? ?? false,
      isGroup: json['isGroup'] as bool? ?? false,
      manuallyAdded: json['manuallyAdded'] as bool? ?? false,
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeenUtc: json['lastSeenUtc'] is String
          ? DateTime.tryParse(json['lastSeenUtc'] as String)
          : null,
      castingRoomId: (json['castingRoomId'] as num?)?.toInt(),
      lastError: json['lastError'] as String?,
    );
  }
}

/// An active cast of one room to one device.
class CastSession {
  final String deviceId;
  final int roomId;
  final bool video;
  final DateTime? startedAtUtc;

  const CastSession({
    required this.deviceId,
    required this.roomId,
    this.video = false,
    this.startedAtUtc,
  });

  factory CastSession.fromJson(Map<String, dynamic> json) {
    return CastSession(
      deviceId: (json['deviceId'] as String?) ?? '',
      roomId: (json['roomId'] as num?)?.toInt() ?? 0,
      video: json['video'] as bool? ?? false,
      startedAtUtc: json['startedAtUtc'] is String
          ? DateTime.tryParse(json['startedAtUtc'] as String)
          : null,
    );
  }
}

/// Outcome of a start request: what began playing, and why the rest did not.
class CastStartResult {
  final List<CastSession> started;
  final Map<String, String> failed;

  const CastStartResult({
    this.started = const <CastSession>[],
    this.failed = const <String, String>{},
  });

  bool get hasFailures => failed.isNotEmpty;

  factory CastStartResult.fromJson(Map<String, dynamic> json) {
    final rawStarted = json['started'];
    final rawFailed = json['failed'];

    return CastStartResult(
      started: rawStarted is List
          ? rawStarted
                .whereType<Map>()
                .map(
                  (raw) => CastSession.fromJson(
                    raw.map((key, value) => MapEntry(key.toString(), value)),
                  ),
                )
                .toList(growable: false)
          : const <CastSession>[],
      failed: rawFailed is Map
          ? rawFailed.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
    );
  }
}
