import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

class PipService {
  static const _channel = MethodChannel('babymonitarr/pip');

  int? _activePipRoomId;
  final ValueNotifier<bool> isInPipMode = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isPreparingForPip = ValueNotifier<bool>(false);

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

  Future<bool> isPipActive() async {
    try {
      final result = await _channel.invokeMethod<bool>('isPipActive');
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

      _activePipRoomId = roomId;
      isPreparingForPip.value = true;

      await SchedulerBinding.instance.endOfFrame;

      final args = <String, dynamic>{
        'roomId': roomId,
        'aspectRatioWidth': 16,
        'aspectRatioHeight': 9,
      };

      final result = await _channel.invokeMethod<bool>('enterPip', args);

      if (result != true) {
        _activePipRoomId = null;
        isPreparingForPip.value = false;
      }
      // Do NOT set isInPipMode here — wait for onPipEntered native callback
      // so the UI doesn't flash to full-screen video before Android enters PIP.
      return result ?? false;
    } catch (_) {
      _activePipRoomId = null;
      isPreparingForPip.value = false;
      return false;
    }
  }

  Future<void> exitPip() async {
    try {
      await _channel.invokeMethod('exitPip');
    } catch (_) {}
    _activePipRoomId = null;
    isInPipMode.value = false;
    isPreparingForPip.value = false;
  }

  Future<dynamic> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onPipDismissed':
        _activePipRoomId = null;
        isInPipMode.value = false;
        isPreparingForPip.value = false;
        break;
      case 'onPipEntered':
        isInPipMode.value = true;
        isPreparingForPip.value = false;
        break;
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    isInPipMode.dispose();
    isPreparingForPip.dispose();
  }
}
