import 'package:flutter_test/flutter_test.dart';

import 'package:dlna_cast/main.dart';

void main() {
  testWidgets('App should render home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DLNACastApp());
    await tester.pumpAndSettle();

    expect(find.text('局域网投屏'), findsOneWidget);
    expect(find.text('设备'), findsOneWidget);
  });
}
