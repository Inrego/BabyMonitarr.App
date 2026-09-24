import 'package:babymonitarr/services/background_restriction_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/background_restrictions');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockChannel(Future<Object?>? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, handler);
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('BackgroundRestrictionStatus.isRestricted', () {
    test('is false when exempt from optimizations and not restricted', () {
      expect(BackgroundRestrictionStatus.unrestricted.isRestricted, isFalse);
    });

    test('is true when battery optimizations apply', () {
      const status = BackgroundRestrictionStatus(
        ignoringBatteryOptimizations: false,
        backgroundRestricted: false,
      );
      expect(status.isRestricted, isTrue);
    });

    test('is true when background usage is restricted', () {
      const status = BackgroundRestrictionStatus(
        ignoringBatteryOptimizations: true,
        backgroundRestricted: true,
      );
      expect(status.isRestricted, isTrue);
    });
  });

  group('BackgroundRestrictionService.getStatus', () {
    test('parses the native status map', () async {
      mockChannel((call) async {
        expect(call.method, 'getStatus');
        return {
          'ignoringBatteryOptimizations': false,
          'backgroundRestricted': true,
        };
      });
      final service = BackgroundRestrictionService(
        channel: channel,
        isAndroid: true,
      );

      expect(
        await service.getStatus(),
        const BackgroundRestrictionStatus(
          ignoringBatteryOptimizations: false,
          backgroundRestricted: true,
        ),
      );
    });

    test('reports unrestricted when the native call fails', () async {
      mockChannel((call) async => throw PlatformException(code: 'boom'));
      final service = BackgroundRestrictionService(
        channel: channel,
        isAndroid: true,
      );

      expect(
        await service.getStatus(),
        BackgroundRestrictionStatus.unrestricted,
      );
    });

    test('skips the native call off Android', () async {
      var called = false;
      mockChannel((call) async {
        called = true;
        return null;
      });
      final service = BackgroundRestrictionService(
        channel: channel,
        isAndroid: false,
      );

      expect(
        await service.getStatus(),
        BackgroundRestrictionStatus.unrestricted,
      );
      expect(called, isFalse);
    });
  });

  group('BackgroundRestrictionService.openSettings', () {
    test('returns the native result', () async {
      mockChannel((call) async {
        expect(call.method, 'openSettings');
        return true;
      });
      final service = BackgroundRestrictionService(
        channel: channel,
        isAndroid: true,
      );

      expect(await service.openSettings(), isTrue);
    });

    test('returns false when the native call fails', () async {
      mockChannel((call) async => throw PlatformException(code: 'boom'));
      final service = BackgroundRestrictionService(
        channel: channel,
        isAndroid: true,
      );

      expect(await service.openSettings(), isFalse);
    });
  });
}
