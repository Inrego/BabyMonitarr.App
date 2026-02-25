import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static const _alertChannelId = 'babymonitarr_alerts';
  static const _alertChannelName = 'Baby Alerts';
  static const _foregroundChannelId = 'babymonitarr_foreground';
  static const _foregroundChannelName = 'Monitoring Active';

  static const _monitoringServiceNotificationId = 1001;
  static const _soundAlertNotificationId = 1002;
  static const _disconnectAlertNotificationId = 1003;
  static const _monitoringServiceChannel = MethodChannel(
    'babymonitarr/monitoring_service',
  );

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _monitoringServiceActive = false;
  bool _disconnectAlertShown = false;

  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      final windowsSettings = WindowsInitializationSettings(
        appName: 'BabyMonitarr',
        appUserModelId: 'com.babymonitarr.app',
        guid: 'd3b07384-d9a3-4f1b-8c2e-5a7e63c1b9f0',
      );
      final initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        windows: windowsSettings,
      );

      await _plugin.initialize(settings: initSettings);
      _initialized = true;
    } catch (_) {}
  }

  Future<void> showAlertNotification({
    required double level,
    required double threshold,
  }) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      _alertChannelId,
      _alertChannelName,
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );
    const windowsDetails = WindowsNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      windows: windowsDetails,
    );

    final absLevel = level.abs().toStringAsFixed(1);
    try {
      await _plugin.show(
        id: _soundAlertNotificationId,
        title: 'Sound Alert',
        body: 'Sound level at $absLevel dB exceeds threshold',
        notificationDetails: details,
      );
    } catch (_) {}
  }

  Future<void> startMonitoringServiceNotification({
    bool reconnecting = false,
    int? roomId,
  }) async {
    await initialize();
    final roomLabel = roomId == null ? '' : ' room $roomId';
    final body = reconnecting
        ? 'Reconnecting$roomLabel. Monitoring stays active.'
        : 'Monitoring$roomLabel is active in the background.';

    const androidDetails = AndroidNotificationDetails(
      _foregroundChannelId,
      _foregroundChannelName,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      enableVibration: false,
      playSound: false,
      onlyAlertOnce: true,
    );

    if (!kIsWeb && Platform.isAndroid) {
      final nativeMethod = _monitoringServiceActive
          ? 'updateMonitoringService'
          : 'startMonitoringService';
      try {
        await _monitoringServiceChannel.invokeMethod<bool>(nativeMethod, {
          'title': 'BabyMonitarr',
          'body': body,
        });
        _monitoringServiceActive = true;
        return;
      } catch (_) {}

      try {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (android != null) {
          await android.startForegroundService(
            id: _monitoringServiceNotificationId,
            title: 'BabyMonitarr',
            body: body,
            notificationDetails: androidDetails,
            startType: AndroidServiceStartType.startSticky,
            foregroundServiceTypes: {
              AndroidServiceForegroundType.foregroundServiceTypeMediaPlayback,
            },
          );
          _monitoringServiceActive = true;
          return;
        }
      } catch (_) {}
    }

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );
    const windowsDetails = WindowsNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      windows: windowsDetails,
    );

    try {
      await _plugin.show(
        id: _monitoringServiceNotificationId,
        title: 'BabyMonitarr',
        body: body,
        notificationDetails: details,
      );
      _monitoringServiceActive = true;
    } catch (_) {}
  }

  Future<void> stopMonitoringServiceNotification() async {
    await initialize();
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _monitoringServiceChannel.invokeMethod<bool>(
          'stopMonitoringService',
        );
      } catch (_) {}
      try {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await android?.stopForegroundService();
      } catch (_) {}
    }
    try {
      await _plugin.cancel(id: _monitoringServiceNotificationId);
    } catch (_) {}
    _monitoringServiceActive = false;
  }

  Future<void> showMonitoringDisconnectedNotification({int? roomId}) async {
    if (_disconnectAlertShown) return;
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      _alertChannelId,
      _alertChannelName,
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );
    const windowsDetails = WindowsNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      windows: windowsDetails,
    );

    final roomSuffix = roomId == null ? '' : ' (room $roomId)';
    try {
      await _plugin.show(
        id: _disconnectAlertNotificationId,
        title: 'Monitoring connection lost$roomSuffix',
        body: 'Trying to reconnect now. Check your network and app state.',
        notificationDetails: details,
      );
      _disconnectAlertShown = true;
    } catch (_) {}
  }

  Future<void> clearMonitoringDisconnectedNotification() async {
    try {
      await _plugin.cancel(id: _disconnectAlertNotificationId);
    } catch (_) {}
    _disconnectAlertShown = false;
  }

  Future<void> showForegroundNotification() {
    return startMonitoringServiceNotification();
  }

  Future<void> cancelForegroundNotification() {
    return stopMonitoringServiceNotification();
  }

  Future<void> cancelAll() async {
    await stopMonitoringServiceNotification();
    try {
      await _plugin.cancelAll();
    } catch (_) {}
    _disconnectAlertShown = false;
  }

  Future<bool> requestPermission() async {
    await initialize();
    if (!kIsWeb && Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }

  Future<void> requestBatteryOptimizationExemption() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}
  }

  bool get isMonitoringServiceActive => _monitoringServiceActive;
}
