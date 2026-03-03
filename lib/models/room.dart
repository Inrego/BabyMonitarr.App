class Room {
  final int id;
  final String name;
  final String icon;
  final String monitorType;
  final bool enableVideoStream;
  final bool enableAudioStream;
  final String? cameraStreamUrl;
  final String? cameraUsername;
  final String? cameraPassword;
  final String streamSourceType;
  final String? nestDeviceId;
  final String? videoSourceCodecName;
  final String? videoPassthroughCodec;
  final String? videoCodecFailureReason;
  final DateTime? videoCodecCheckedAtUtc;
  final bool isActive;
  final DateTime? createdAt;

  const Room({
    this.id = 0,
    this.name = '',
    this.icon = 'baby',
    this.monitorType = 'camera_audio',
    this.enableVideoStream = false,
    this.enableAudioStream = true,
    this.cameraStreamUrl,
    this.cameraUsername,
    this.cameraPassword,
    this.streamSourceType = 'rtsp',
    this.nestDeviceId,
    this.videoSourceCodecName,
    this.videoPassthroughCodec,
    this.videoCodecFailureReason,
    this.videoCodecCheckedAtUtc,
    this.isActive = false,
    this.createdAt,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      icon: (json['icon'] as String?) ?? 'baby',
      monitorType: (json['monitorType'] as String?) ?? 'camera_audio',
      enableVideoStream: json['enableVideoStream'] as bool? ?? false,
      enableAudioStream: json['enableAudioStream'] as bool? ?? true,
      cameraStreamUrl: json['cameraStreamUrl'] as String?,
      cameraUsername: json['cameraUsername'] as String?,
      cameraPassword: json['cameraPassword'] as String?,
      streamSourceType: (json['streamSourceType'] as String?) ?? 'rtsp',
      nestDeviceId: json['nestDeviceId'] as String?,
      videoSourceCodecName: json['videoSourceCodecName'] as String?,
      videoPassthroughCodec: json['videoPassthroughCodec'] as String?,
      videoCodecFailureReason: json['videoCodecFailureReason'] as String?,
      videoCodecCheckedAtUtc: json['videoCodecCheckedAtUtc'] is String
          ? DateTime.tryParse(json['videoCodecCheckedAtUtc'] as String)
          : null,
      isActive: json['isActive'] as bool? ?? false,
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'monitorType': monitorType,
      'enableVideoStream': enableVideoStream,
      'enableAudioStream': enableAudioStream,
      'cameraStreamUrl': cameraStreamUrl ?? '',
      'cameraUsername': cameraUsername ?? '',
      'cameraPassword': cameraPassword ?? '',
      'streamSourceType': streamSourceType,
      'nestDeviceId': nestDeviceId ?? '',
      'videoSourceCodecName': videoSourceCodecName,
      'videoPassthroughCodec': videoPassthroughCodec,
      'videoCodecFailureReason': videoCodecFailureReason,
      'videoCodecCheckedAtUtc': videoCodecCheckedAtUtc?.toIso8601String(),
      'isActive': isActive,
    };
  }

  Room copyWith({
    int? id,
    String? name,
    String? icon,
    String? monitorType,
    bool? enableVideoStream,
    bool? enableAudioStream,
    String? cameraStreamUrl,
    String? cameraUsername,
    String? cameraPassword,
    String? streamSourceType,
    String? nestDeviceId,
    String? videoSourceCodecName,
    String? videoPassthroughCodec,
    String? videoCodecFailureReason,
    DateTime? videoCodecCheckedAtUtc,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      monitorType: monitorType ?? this.monitorType,
      enableVideoStream: enableVideoStream ?? this.enableVideoStream,
      enableAudioStream: enableAudioStream ?? this.enableAudioStream,
      cameraStreamUrl: cameraStreamUrl ?? this.cameraStreamUrl,
      cameraUsername: cameraUsername ?? this.cameraUsername,
      cameraPassword: cameraPassword ?? this.cameraPassword,
      streamSourceType: streamSourceType ?? this.streamSourceType,
      nestDeviceId: nestDeviceId ?? this.nestDeviceId,
      videoSourceCodecName: videoSourceCodecName ?? this.videoSourceCodecName,
      videoPassthroughCodec:
          videoPassthroughCodec ?? this.videoPassthroughCodec,
      videoCodecFailureReason:
          videoCodecFailureReason ?? this.videoCodecFailureReason,
      videoCodecCheckedAtUtc:
          videoCodecCheckedAtUtc ?? this.videoCodecCheckedAtUtc,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
