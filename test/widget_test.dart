import 'package:flutter_test/flutter_test.dart';
import 'package:babymonitarr/main.dart';

void main() {
  testWidgets('App starts successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const BabyMonitarrApp());
    await tester.pump();
  });
}
