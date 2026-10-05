import 'package:babymonitarr/models/audio_state.dart';
import 'package:babymonitarr/widgets/sound_level_graph.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SoundLevelGraph', () {
    testWidgets('does not animate between history updates', (tester) async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final history = List.generate(
        10,
        (i) => AudioLevel(
          level: i.isEven ? -60 : -20,
          timestamp: nowMs - (10 - i) * 500,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SoundLevelGraph(
              history: history,
              currentDisplayLevel: 30,
              currentStatus: SoundStatus.quiet,
            ),
          ),
        ),
      );

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.duration, Duration.zero);
    });
  });
}
