import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Receives log lines from native Android code (see `NativeLog.kt`) and
/// writes them to `Logger('Native.<logger>')`, so they land in the persistent
/// file log alongside Dart events.
class NativeLogBridge {
  NativeLogBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'babymonitarr/native_log';

  final MethodChannel _channel;

  void register() {
    _channel.setMethodCallHandler(handleCall);
  }

  void unregister() {
    _channel.setMethodCallHandler(null);
  }

  Future<Object?> handleCall(MethodCall call) async {
    if (call.method != 'log') {
      throw MissingPluginException('Unknown method ${call.method}');
    }
    final args = call.arguments is Map
        ? call.arguments as Map<Object?, Object?>
        : const <Object?, Object?>{};
    final loggerName = args['logger'] as String? ?? 'Unknown';
    final message = args['message'] as String? ?? '';
    final error = args['error'] as String?;
    Logger(
      'Native.$loggerName',
    ).log(levelFor(args['level'] as String?), message, error);
    return null;
  }

  static Level levelFor(String? name) {
    switch (name) {
      case 'SEVERE':
        return Level.SEVERE;
      case 'WARNING':
        return Level.WARNING;
      default:
        return Level.INFO;
    }
  }
}
