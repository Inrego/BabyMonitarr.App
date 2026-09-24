import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

final _log = Logger('BackgroundRestrictionService');

/// The OS-level background settings Android exposes to the app itself.
///
/// OEM freezers (e.g. ColorOS "Hans") keep their own state behind system-only
/// permissions, so a clean status here does not guarantee the app survives
/// the night — it only rules out the restrictions we can see.
@immutable
class BackgroundRestrictionStatus {
  final bool ignoringBatteryOptimizations;
  final bool backgroundRestricted;

  const BackgroundRestrictionStatus({
    required this.ignoringBatteryOptimizations,
    required this.backgroundRestricted,
  });

  static const unrestricted = BackgroundRestrictionStatus(
    ignoringBatteryOptimizations: true,
    backgroundRestricted: false,
  );

  factory BackgroundRestrictionStatus.fromMap(Map<Object?, Object?> map) {
    return BackgroundRestrictionStatus(
      ignoringBatteryOptimizations:
          map['ignoringBatteryOptimizations'] as bool? ?? true,
      backgroundRestricted: map['backgroundRestricted'] as bool? ?? false,
    );
  }

  bool get isRestricted =>
      !ignoringBatteryOptimizations || backgroundRestricted;

  @override
  bool operator ==(Object other) =>
      other is BackgroundRestrictionStatus &&
      other.ignoringBatteryOptimizations == ignoringBatteryOptimizations &&
      other.backgroundRestricted == backgroundRestricted;

  @override
  int get hashCode =>
      Object.hash(ignoringBatteryOptimizations, backgroundRestricted);

  @override
  String toString() =>
      'BackgroundRestrictionStatus(ignoringBatteryOptimizations: '
      '$ignoringBatteryOptimizations, backgroundRestricted: '
      '$backgroundRestricted)';
}

class BackgroundRestrictionService {
  static const _defaultChannel = MethodChannel(
    'babymonitarr/background_restrictions',
  );

  final MethodChannel _channel;
  final bool _isAndroid;

  BackgroundRestrictionService({MethodChannel? channel, bool? isAndroid})
    : _channel = channel ?? _defaultChannel,
      _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid);

  /// Unknown or unsupported platforms report [BackgroundRestrictionStatus.unrestricted]
  /// so the UI never nags on a failed check.
  Future<BackgroundRestrictionStatus> getStatus() async {
    if (!_isAndroid) return BackgroundRestrictionStatus.unrestricted;
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>('getStatus');
      if (map == null) return BackgroundRestrictionStatus.unrestricted;
      return BackgroundRestrictionStatus.fromMap(map);
    } catch (e, st) {
      _log.warning('Failed to read background restriction status', e, st);
      return BackgroundRestrictionStatus.unrestricted;
    }
  }

  Future<bool> openSettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (e, st) {
      _log.warning('Failed to open background usage settings', e, st);
      return false;
    }
  }
}
