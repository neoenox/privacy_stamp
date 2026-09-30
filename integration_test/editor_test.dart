import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:privacy_stamp/main.dart';
import 'package:privacy_stamp/test_harness.dart';
import 'package:privacy_stamp/features/redaction/presentation/stamp_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('editor: tap canvas places mask', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));

    final controller = StampController.testInstance();

    await tester.pumpWidget(
      MaterialApp(
        home: TestHarness(
          controller: controller,
          child: StampHomePage(controller: controller),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(controller.hasImage, isTrue, reason: 'fixture should be loaded');
    expect(controller.manualStamps, isEmpty, reason: 'no masks yet');

    final canvas = find.byType(Image);
    expect(canvas, findsOneWidget);

    await tester.tap(canvas);
    await tester.pumpAndSettle();

    expect(controller.manualStamps, hasLength(1), reason: 'one mask placed');
  });

  testWidgets('editor: export succeeds', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));

    final controller = StampController.testInstance();

    await tester.pumpWidget(
      MaterialApp(
        home: TestHarness(
          controller: controller,
          child: StampHomePage(controller: controller),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 5));

    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();

    final exportButton = find.widgetWithText(FilledButton, '書き出す');
    expect(exportButton, findsOneWidget);

    await tester.tap(exportButton);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Export requires explicit review confirmation.
    await tester.tap(find.text('確認して書き出す'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(controller.exportCount, greaterThan(0), reason: 'export recorded');
  });
}
