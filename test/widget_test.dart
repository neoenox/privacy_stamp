import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/stamp_controller.dart';
import 'package:privacy_stamp/main.dart';

void main() {
  testWidgets('shows local-only image picker landing screen', (tester) async {
    await tester.pumpWidget(const PrivacyStampApp());
    expect(find.text('画像を選ぶ'), findsOneWidget);
    expect(find.textContaining('端末・ブラウザー内'), findsOneWidget);
  });

  testWidgets('explains manual-only editing and exposes accessible controls', (
    tester,
  ) async {
    final controller = StampController(
      picker: _FakePicker(),
      detector: _FakeDetector(),
      exporter: (source, stamps) => Uint8List.fromList([1]),
      saver: _FakeSaver(),
      history: _FakeHistory(),
    );
    await tester.pumpWidget(
      PrivacyStampApp(home: StampHomePage(controller: controller)),
    );
    await controller.pickImage();
    await tester.pump();

    expect(
      find.textContaining('顔・文字・バーコードの候補は自動で追加されます'),
      findsOneWidget,
    );
    expect(find.text('文字をすべて隠す'), findsNothing);
    expect(
      find.bySemanticsLabel('画像編集領域。画像上をタップすると手動マスクを追加します。'),
      findsOneWidget,
    );

    await tester.tap(find.text('手動スタンプを追加'));
    await tester.pump();
    await tester.tap(find.text('手動'));
    await tester.pump();
    expect(find.text('左へ'), findsOneWidget);
    expect(find.text('大きく'), findsOneWidget);
    expect(find.text('削除'), findsOneWidget);

    final stamp = controller.manualStamps.single;
    final leftBefore = stamp.rect.left;
    await tester.ensureVisible(find.text('左へ'));
    await tester.tap(find.text('左へ'));
    await tester.pump();
    expect(controller.manualStamps.single.rect.left, lessThan(leftBefore));
  });

  testWidgets('ignores taps in the contain letterbox outside the image', (
    tester,
  ) async {
    final controller = StampController(
      picker: _FakePicker(),
      detector: _FakeDetector(),
      exporter: (source, stamps) => Uint8List.fromList([1]),
      saver: _FakeSaver(),
      history: _FakeHistory(),
    );
    await tester.pumpWidget(
      PrivacyStampApp(home: StampHomePage(controller: controller)),
    );
    await controller.pickImage();
    await tester.pump();

    final canvas = tester.getRect(
      find.byKey(const ValueKey('image-editor-canvas')),
    );
    await tester.tapAt(canvas.topCenter + const Offset(0, 2));
    await tester.pump();
    expect(find.text('0 件のマスク'), findsOneWidget);
  });

  testWidgets('export review cancellation does not save the image', (
    tester,
  ) async {
    const reviewMessage =
        '顔・文字・バーコードの自動検出は目安です。'
        '隠し忘れがないか、'
        '画像全体を確認してから書き出してください。';
    final saver = _FakeSaver();
    final controller = StampController(
      picker: _FakePicker(),
      detector: _FakeDetector(),
      exporter: (source, stamps) => Uint8List.fromList([1]),
      saver: saver,
      history: _FakeHistory(),
    );
    await tester.pumpWidget(
      PrivacyStampApp(home: StampHomePage(controller: controller)),
    );
    await controller.pickImage();
    controller.addManualStamp();
    await tester.pump();

    await tester.ensureVisible(find.text('書き出す'));
    await tester.tap(find.text('書き出す'));
    await tester.pumpAndSettle();

    expect(find.text('書き出す前に確認してください'), findsOneWidget);
    expect(find.text(reviewMessage), findsOneWidget);

    await tester.tap(find.text('戻って確認する'));
    await tester.pumpAndSettle();

    expect(saver.saveCount, 0);
  });

  testWidgets('export starts only after explicit review confirmation', (
    tester,
  ) async {
    final saver = _FakeSaver();
    final controller = StampController(
      picker: _FakePicker(),
      detector: _FakeDetector(),
      exporter: (source, stamps) => Uint8List.fromList([1]),
      saver: saver,
      history: _FakeHistory(),
    );
    await tester.pumpWidget(
      PrivacyStampApp(home: StampHomePage(controller: controller)),
    );
    await controller.pickImage();
    controller.addManualStamp();
    await tester.pump();

    await tester.ensureVisible(find.text('書き出す'));
    await tester.tap(find.text('書き出す'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認して書き出す'));
    await tester.pumpAndSettle();

    expect(saver.saveCount, 1);
    expect(find.textContaining('元画像とは別のPNG'), findsOneWidget);
  });
}

class _FakePicker implements ImagePickerGateway {
  @override
  Future<PickedImage?> pick() async => const PickedImage(
    bytes: [1, 2, 3],
    name: 'test.png',
    imageSize: PixelSize(200, 100),
  );
}

class _FakeDetector implements DetectionGateway {
  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) async =>
      const [];
}

class _FakeSaver implements ImageSaverGateway {
  int saveCount = 0;

  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async {
    saveCount++;
    return true;
  }
}

class _FakeHistory implements ExportHistoryGateway {
  @override
  Future<int> readCount() async => 0;

  @override
  Future<void> recordExport() async {}
}
