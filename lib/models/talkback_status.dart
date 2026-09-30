/// Server-side talkback lifecycle for a room (`TalkbackStatus.state`).
enum TalkbackState { closed, connecting, open, talking }

/// Why talkback can't be used right now. Mirrors the backend's
/// `unavailableReason` / `TalkbackStartResult.reason` strings.
class TalkbackReason {
  static const notNest = 'not_nest';
  static const notConfigured = 'not_configured';
  static const credentialFailing = 'credential_failing';
  static const cameraNotMapped = 'camera_not_mapped';
  static const cameraError = 'camera_error';
  static const busy = 'busy';
  static const cancelled = 'cancelled';

  const TalkbackReason._();

  /// Fallback text for when the server sends a reason without a message.
  static String describe(String? reason) {
    switch (reason) {
      case notNest:
        return 'This room has no camera speaker';
      case notConfigured:
        return 'Talkback is not set up on the server';
      case credentialFailing:
        return 'The Google Home sign-in on the server has expired';
      case cameraNotMapped:
        return 'No camera is linked to this room for talkback';
      case cameraError:
        return 'Could not reach the camera speaker. Try again.';
      case busy:
        return 'Someone else is talking in this room';
      default:
        return 'Talkback is unavailable';
    }
  }
}

class TalkbackStatus {
  final int roomId;
  final bool supported;
  final bool available;
  final String? unavailableReason;
  final String? message;
  final TalkbackState state;
  final bool busy;
  final double volume;

  const TalkbackStatus({
    required this.roomId,
    this.supported = false,
    this.available = false,
    this.unavailableReason,
    this.message,
    this.state = TalkbackState.closed,
    this.busy = false,
    this.volume = 1.0,
  });

  factory TalkbackStatus.fromJson(Map<String, dynamic> json) {
    return TalkbackStatus(
      roomId: _asInt(json['roomId']) ?? 0,
      supported: json['supported'] == true,
      available: json['available'] == true,
      unavailableReason: _asNonEmptyString(json['unavailableReason']),
      message: _asNonEmptyString(json['message']),
      state: parseState(json['state']),
      busy: json['busy'] == true,
      volume: clampVolume((json['volume'] as num?)?.toDouble() ?? 1.0),
    );
  }

  /// Text to show next to a disabled or failed Talk button.
  String get displayMessage =>
      message ?? TalkbackReason.describe(unavailableReason);

  TalkbackStatus copyWith({double? volume}) {
    return TalkbackStatus(
      roomId: roomId,
      supported: supported,
      available: available,
      unavailableReason: unavailableReason,
      message: message,
      state: state,
      busy: busy,
      volume: volume ?? this.volume,
    );
  }

  static TalkbackState parseState(Object? raw) {
    switch (raw is String ? raw.toLowerCase() : null) {
      case 'connecting':
        return TalkbackState.connecting;
      case 'open':
        return TalkbackState.open;
      case 'talking':
        return TalkbackState.talking;
      default:
        return TalkbackState.closed;
    }
  }

  static double clampVolume(double volume) {
    if (volume.isNaN) return 1.0;
    return volume.clamp(0.0, 2.0).toDouble();
  }
}

class TalkbackStartResult {
  final bool success;
  final String? reason;
  final String? message;

  const TalkbackStartResult({required this.success, this.reason, this.message});

  factory TalkbackStartResult.fromJson(Map<String, dynamic> json) {
    return TalkbackStartResult(
      success: json['success'] == true,
      reason: _asNonEmptyString(json['reason']),
      message: _asNonEmptyString(json['message']),
    );
  }

  bool get cancelled => reason == TalkbackReason.cancelled;

  String get displayMessage => message ?? TalkbackReason.describe(reason);
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _asNonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
