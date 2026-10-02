import 'package:cutnsave/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows app name', (tester) async {
    await tester.pumpWidget(const CutNSaveApp());
    expect(find.text('cutNsave'), findsOneWidget);
  });
}
