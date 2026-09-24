import 'package:babymonitarr/widgets/background_restriction_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('open settings button invokes the callback', (
    WidgetTester tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackgroundRestrictionCard(onOpenSettings: () => opened++),
        ),
      ),
    );

    expect(find.text('Background usage is restricted'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    expect(opened, 1);
  });
}
