import 'dart:async';

import 'package:babymonitarr/models/talkback_status.dart';
import 'package:babymonitarr/providers/talkback_provider.dart';
import 'package:babymonitarr/widgets/talkback_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../providers/talkback_fakes.dart';

void main() {
  late FakeTalkbackHub hub;
  late FakeAudioControl audio;
  late bool micGranted;
  late TalkbackProvider provider;

  setUp(() {
    hub = FakeTalkbackHub();
    audio = FakeAudioControl();
    micGranted = true;
    provider = TalkbackProvider(
      uplinkFactory: FakeUplink.new,
      requestMicPermission: () async => micGranted,
    )..attach(hub: hub, audio: audio);
  });

  tearDown(() {
    hub.dispose();
  });

  Future<void> pumpPanel(WidgetTester tester, TalkbackStatus status) async {
    hub.statuses[status.roomId] = status;
    await tester.pumpWidget(
      ChangeNotifierProvider<TalkbackProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(body: TalkbackPanel(roomId: status.roomId)),
        ),
      ),
    );
    await tester.pump();
  }

  Finder talkButton() => find.byKey(TalkbackPanel.talkButtonKey);

  String? messageText(WidgetTester tester) {
    final finder = find.byKey(TalkbackPanel.messageKey);
    if (finder.evaluate().isEmpty) return null;
    return tester.widget<Text>(finder).data;
  }

  testWidgets('hidden when the room is not supported', (tester) async {
    await pumpPanel(tester, const TalkbackStatus(roomId: 3));

    expect(talkButton(), findsNothing);
    expect(find.byKey(TalkbackPanel.volumeSliderKey), findsNothing);
  });

  testWidgets('shows Hold to talk and volume when available', (tester) async {
    await pumpPanel(tester, availableStatus(3, volume: 1.5));

    expect(find.text('Hold to talk'), findsOneWidget);
    expect(messageText(tester), isNull);
    expect(find.text('150 %'), findsOneWidget);
  });

  testWidgets('disabled with the server message when unavailable', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      const TalkbackStatus(
        roomId: 3,
        supported: true,
        available: false,
        unavailableReason: 'credential_failing',
        message: 'Google Home sign-in expired',
      ),
    );

    expect(find.text('Talk unavailable'), findsOneWidget);
    expect(messageText(tester), 'Google Home sign-in expired');

    await tester.press(talkButton());
    await tester.pump();
    expect(hub.calls, isNot(contains('StartTalkback(3)')));
  });

  testWidgets('camera not mapped falls back to a description', (tester) async {
    await pumpPanel(
      tester,
      const TalkbackStatus(
        roomId: 3,
        supported: true,
        available: false,
        unavailableReason: 'camera_not_mapped',
      ),
    );

    expect(
      messageText(tester),
      TalkbackReason.describe(TalkbackReason.cameraNotMapped),
    );
  });

  testWidgets('camera error keeps the button enabled with a hint', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      const TalkbackStatus(
        roomId: 3,
        supported: true,
        available: true,
        unavailableReason: 'camera_error',
        message: 'Camera did not answer',
      ),
    );

    expect(find.text('Hold to talk'), findsOneWidget);
    expect(messageText(tester), 'Camera did not answer');
  });

  testWidgets('busy elsewhere disables the button', (tester) async {
    await pumpPanel(
      tester,
      const TalkbackStatus(
        roomId: 3,
        supported: true,
        available: true,
        state: TalkbackState.talking,
        busy: true,
      ),
    );

    expect(find.text('Someone is talking'), findsOneWidget);
    expect(messageText(tester), TalkbackReason.describe(TalkbackReason.busy));
  });

  testWidgets('press shows connecting, then talking, release stops', (
    tester,
  ) async {
    await pumpPanel(tester, availableStatus(3));
    hub.startCompleter = Completer<TalkbackStartResult>();

    final gesture = await tester.startGesture(tester.getCenter(talkButton()));
    await tester.pump();
    expect(find.text('Connecting…'), findsOneWidget);

    hub.startCompleter!.complete(const TalkbackStartResult(success: true));
    await tester.pump();
    await tester.pump();
    expect(find.text('Talking – release to stop'), findsOneWidget);
    expect(audio.calls, ['begin(3)']);

    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(find.text('Hold to talk'), findsOneWidget);
    expect(hub.calls, contains('StopTalkback(3)'));
    expect(hub.calls.last, 'StopTalkbackUplink(3)');
    expect(audio.calls, ['begin(3)', 'end(3)']);
  });

  testWidgets('mic permission denied shows a message', (tester) async {
    micGranted = false;
    await pumpPanel(tester, availableStatus(3));

    final gesture = await tester.startGesture(tester.getCenter(talkButton()));
    await tester.pump();
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(find.text('Hold to talk'), findsOneWidget);
    expect(messageText(tester), contains('Microphone permission'));
  });

  testWidgets('volume slider sends a debounced SetTalkbackVolume', (
    tester,
  ) async {
    await pumpPanel(tester, availableStatus(3));

    final slider = find.byKey(TalkbackPanel.volumeSliderKey);
    await tester.tapAt(tester.getTopRight(slider) + const Offset(-24, 24));
    await tester.pump();
    expect(hub.volumes, isEmpty);

    await tester.pump(
      TalkbackProvider.volumeDebounce + const Duration(milliseconds: 10),
    );
    expect(hub.volumes, hasLength(1));
    expect(hub.volumes.single, greaterThan(1.5));
  });

  testWidgets('leaving the screen while talking stops talking', (tester) async {
    await pumpPanel(tester, availableStatus(3));

    final gesture = await tester.startGesture(tester.getCenter(talkButton()));
    await tester.pump();
    await tester.pump();
    expect(provider.phaseFor(3), TalkPhase.talking);

    await tester.pumpWidget(
      ChangeNotifierProvider<TalkbackProvider>.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: SizedBox())),
      ),
    );
    await tester.pump();
    await gesture.up();

    expect(provider.phaseFor(3), TalkPhase.idle);
    expect(hub.calls, contains('StopTalkback(3)'));
  });
}
