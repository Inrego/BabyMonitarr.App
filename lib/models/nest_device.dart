class NestDevice {
  final String deviceId;
  final String displayName;
  final String roomName;

  const NestDevice({
    required this.deviceId,
    required this.displayName,
    required this.roomName,
  });

  factory NestDevice.fromJson(Map<String, dynamic> json) {
    return NestDevice(
      deviceId: (json['deviceId'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '',
      roomName: (json['roomName'] as String?) ?? '',
    );
  }

  String get label {
    if (displayName.isNotEmpty && roomName.isNotEmpty) {
      return '$displayName ($roomName)';
    }
    if (displayName.isNotEmpty) {
      return displayName;
    }
    if (roomName.isNotEmpty) {
      return roomName;
    }
    return deviceId;
  }
}
