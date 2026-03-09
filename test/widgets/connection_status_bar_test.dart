import 'package:babymonitarr/models/connection_state.dart';
import 'package:babymonitarr/widgets/connection_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('does not show manual reconnect copy when disconnected', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConnectionStatusBar(
            info: ConnectionInfo(state: MonitorConnectionState.disconnected),
          ),
        ),
      ),
    );

    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('Tap to reconnect'), findsNothing);
  });
}
