import 'package:flutter_test/flutter_test.dart';

import 'package:dlna_cast/main.dart';

void main() {
  testWidgets('App should render home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DLNACastApp());
    await tester.pumpAndSettle();

    expect(find.text('DLNA Cast'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
  });
}
