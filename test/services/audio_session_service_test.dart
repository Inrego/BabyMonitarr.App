import 'package:babymonitarr/services/audio_session_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioSessionService talkback', () {
    test('begin and end toggle the talkback configuration', () async {
      final service = AudioSessionService();
      expect(service.isTalkbackActive, isFalse);

      await service.beginTalkback();
      expect(service.isTalkbackActive, isTrue);

      // A monitoring reconnect mid-talk re-applies config but keeps talkback.
      await service.ensureConfigured();
      expect(service.isTalkbackActive, isTrue);

      await service.endTalkback();
      expect(service.isTalkbackActive, isFalse);
    });

    test('endTalkback without begin is a no-op', () async {
      final service = AudioSessionService();

      await service.endTalkback();

      expect(service.isTalkbackActive, isFalse);
    });
  });
}
