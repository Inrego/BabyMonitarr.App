import 'package:babymonitarr/providers/connection_provider.dart';
import 'package:babymonitarr/services/audio_session_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAudioSession extends AudioSessionService {
  final List<String> calls = <String>[];

  @override
  Future<void> beginTalkback() async => calls.add('begin');

  @override
  Future<void> endTalkback() async => calls.add('end');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('talkback mutes the room and restores the session last', () async {
    final session = _RecordingAudioSession();
    final provider = ConnectionProvider(audioSession: session);
    addTearDown(provider.dispose);

    await provider.beginTalkback(3);
    expect(provider.isTalkbackDucked(3), isTrue);
    expect(provider.isTalkbackDucked(4), isFalse);
    expect(session.calls, ['begin']);

    await provider.endTalkback(3);
    expect(provider.isTalkbackDucked(3), isFalse);
    expect(session.calls, ['begin', 'end']);
  });
}
