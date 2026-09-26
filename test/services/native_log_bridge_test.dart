import 'dart:async';

import 'package:babymonitarr/services/native_log_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/native_log');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late NativeLogBridge bridge;
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;
  late Level previousLevel;

  setUp(() {
    previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    records = [];
    sub = Logger.root.onRecord.listen(records.add);
    bridge = NativeLogBridge(channel: channel)..register();
  });

  tearDown(() async {
    bridge.unregister();
    await sub.cancel();
    Logger.root.level = previousLevel;
  });

  Future<void> sendFromNative(String method, Object? args) async {
    final completer = Completer<void>();
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) => completer.complete(),
    );
    await completer.future;
  }

  group('NativeLogBridge', () {
    test('maps INFO to Level.INFO under Native.<logger>', () async {
      await sendFromNative('log', {
        'level': 'INFO',
        'logger': 'MonitoringService',
        'message': 'Audio focus requested: granted',
        'error': null,
      });

      expect(records, hasLength(1));
      expect(records.single.level, Level.INFO);
      expect(records.single.loggerName, 'Native.MonitoringService');
      expect(records.single.message, 'Audio focus requested: granted');
      expect(records.single.error, isNull);
    });

    test('maps WARNING and passes the error text through', () async {
      await sendFromNative('log', {
        'level': 'WARNING',
        'logger': 'MonitoringService',
        'message': 'Failed to acquire wake lock',
        'error': 'java.lang.SecurityException: nope',
      });

      expect(records.single.level, Level.WARNING);
      expect(records.single.error, 'java.lang.SecurityException: nope');
    });

    test('maps SEVERE to Level.SEVERE', () async {
      await sendFromNative('log', {
        'level': 'SEVERE',
        'logger': 'X',
        'message': 'boom',
      });

      expect(records.single.level, Level.SEVERE);
      expect(records.single.loggerName, 'Native.X');
    });

    test('falls back to INFO for unknown levels', () {
      expect(NativeLogBridge.levelFor('DEBUG'), Level.INFO);
      expect(NativeLogBridge.levelFor(null), Level.INFO);
    });

    test('ignores unknown methods without logging', () async {
      await sendFromNative('other', null);
      expect(records, isEmpty);
    });
  });
}
