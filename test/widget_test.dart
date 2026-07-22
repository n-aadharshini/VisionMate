import 'package:flutter_test/flutter_test.dart';
import 'package:vision_mate/main.dart';

void main() {
  testWidgets('VisionMate opens on the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const VisionMateApp());

    expect(find.text('VisionMate'), findsOneWidget);
    expect(find.text('Tap anywhere to begin'), findsOneWidget);
  });
}
