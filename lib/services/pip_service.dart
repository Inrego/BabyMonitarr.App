import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PipService {
  static const _channel = MethodChannel('babymonitarr/pip');

  int? _activePipRoomId;
  final ValueNotifier<bool> isInPipMode = ValueNotifier<bool>(false);

  int? get activePipRoomId => _activePipRoomId;

  PipService() {
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  Future<bool> isPipSupported() async {
    try {
      final result = await _channel.invokeMethod<bool>('isPipSupported');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> enterPip({required int roomId}) async {
    try {
      if (isInPipMode.value && _activePipRoomId != roomId) {
        await exitPip();
      }

      final result = await _channel.invokeMethod<bool>('enterPip', {
        'roomId': roomId,
        'aspectRatioWidth': 16,
        'aspectRatioHeight': 9,
      });

      if (result == true) {
        _activePipRoomId = roomId;
        isInPipMode.value = true;
      }
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> exitPip() async {
    try {
      await _channel.invokeMethod('exitPip');
    } catch (_) {}
    _activePipRoomId = null;
    isInPipMode.value = false;
  }

  Future<dynamic> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onPipDismissed':
        _activePipRoomId = null;
        isInPipMode.value = false;
        break;
      case 'onPipEntered':
        isInPipMode.value = true;
        break;
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    isInPipMode.dispose();
  }
}
