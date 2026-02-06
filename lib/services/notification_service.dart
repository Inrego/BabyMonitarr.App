import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static const _alertChannelId = 'babymonitarr_alerts';
  static const _alertChannelName = 'Baby Alerts';
  static const _foregroundChannelId = 'babymonitarr_foreground';
  static const _foregroundChannelName = 'Monitoring Active';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
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
  }

  Future<void> showAlertNotification({
    required double level,
    required double threshold,
  }) async {
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
    await _plugin.show(
      id: 1,
      title: 'Sound Alert',
      body: 'Sound level at $absLevel dB exceeds threshold',
      notificationDetails: details,
    );
  }

  Future<void> showForegroundNotification() async {
    const androidDetails = AndroidNotificationDetails(
      _foregroundChannelId,
      _foregroundChannelName,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      enableVibration: false,
      playSound: false,
    );
    const windowsDetails = WindowsNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      windows: windowsDetails,
    );

    await _plugin.show(
      id: 0,
      title: 'BabyMonitarr',
      body: 'Monitoring active',
      notificationDetails: details,
    );
  }

  Future<void> cancelForegroundNotification() async {
    await _plugin.cancel(id: 0);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  Future<bool> requestPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }
}
