import 'package:flutter_test/flutter_test.dart';
import 'package:babymonitarr/main.dart';
import 'package:babymonitarr/services/audio_session_service.dart';

void main() {
  testWidgets('App starts successfully', (WidgetTester tester) async {
    await tester.pumpWidget(BabyMonitarrApp(audioSession: AudioSessionService()));
    await tester.pump();
  });
}
