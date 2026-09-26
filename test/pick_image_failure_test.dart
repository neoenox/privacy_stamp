import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/stamp_controller.dart';
import 'package:privacy_stamp/main.dart';

void main() {
  test('picker cancellation is not reported as an error', () async {
    final controller = _controller(picker: _QueuePicker(<Object?>[null]));

    final result = await controller.pickImage();

    expect(result, PickImageResult.cancelled);
    expect(controller.pickFailure, isNull);
    expect(controller.hasImage, isFalse);
    expect(controller.isBusy, isFalse);
  });

  test(
    'picker failure is retryable and a later success clears the error',
    () async {
      final controller = _controller(
        picker: _QueuePicker(<Object?>[
          const ImagePickException(PickImageFailure.picker),
          const _PickedImage(),
        ]),
      );

      final failed = await controller.pickImage();
      expect(failed, PickImageResult.pickerFailed);
      expect(controller.pickFailure, PickImageFailure.picker);
      expect(controller.hasImage, isFalse);
      expect(controller.isBusy, isFalse);

      final succeeded = await controller.pickImage();
      expect(succeeded, PickImageResult.detectionEmpty);
      expect(controller.pickFailure, isNull);
      expect(controller.hasImage, isTrue);
    },
  );

  test(
    'decode failure is categorized without exposing internal details',
    () async {
      final controller = _controller(
        picker: _QueuePicker(<Object?>[
          const ImagePickException(PickImageFailure.decode),
        ]),
      );

      final result = await controller.pickImage();

      expect(result, PickImageResult.decodeFailed);
      expect(controller.pickFailure, PickImageFailure.decode);
      expect(controller.hasImage, isFalse);
      expect(controller.isBusy, isFalse);
    },
  );

  test('detection failure keeps the selected image editable', () async {
    final controller = _controller(
      picker: _QueuePicker(<Object?>[const _PickedImage()]),
      detector: _ThrowingDetector(),
    );

    final result = await controller.pickImage();

    expect(result, PickImageResult.detectionFailed);
    expect(controller.pickFailure, PickImageFailure.detectionFailed);
    expect(controller.hasImage, isTrue);
    expect(controller.detections, isEmpty);
    expect(controller.isBusy, isFalse);

    controller.addManualStamp();
    expect(controller.manualStamps, hasLength(1));
  });

  testWidgets('shows a generic retryable message for picker failures', (
    tester,
  ) async {
    final controller = _controller(
      picker: _QueuePicker(<Object?>[Exception('secret path: /tmp/private')]),
    );
    await tester.pumpWidget(
      PrivacyStampApp(home: StampHomePage(controller: controller)),
    );

    await tester.tap(find.text('画像を選ぶ'));
    await tester.pumpAndSettle();

    expect(find.text('画像を選択できませんでした。もう一度お試しください。'), findsOneWidget);
    expect(find.textContaining('/tmp/private'), findsNothing);
    expect(find.text('画像を選ぶ'), findsOneWidget);
  });

  testWidgets('shows decode guidance and remains on the picker', (
    tester,
  ) async {
    final controller = _controller(
      picker: _QueuePicker(<Object?>[
        const ImagePickException(PickImageFailure.decode),
      ]),
    );
    await tester.pumpWidget(
      PrivacyStampApp(home: StampHomePage(controller: controller)),
    );

    await tester.tap(find.text('画像を選ぶ'));
    await tester.pumpAndSettle();

    expect(find.text('この画像を読み込めませんでした。別の画像を選んでください。'), findsOneWidget);
    expect(find.text('画像を選ぶ'), findsOneWidget);
  });

  testWidgets('detection failure opens the manual editor with guidance', (
    tester,
  ) async {
    final controller = _controller(
      picker: _QueuePicker(<Object?>[const _PickedImage()]),
      detector: _ThrowingDetector(),
    );
    await tester.pumpWidget(
      PrivacyStampApp(home: StampHomePage(controller: controller)),
    );

    await tester.tap(find.text('画像を選ぶ'));
    await tester.pumpAndSettle();

    expect(find.text('画像の自動確認に失敗しました。画像は手動で編集できます。'), findsOneWidget);
    expect(find.text('手動スタンプを追加'), findsOneWidget);
  });
}

StampController _controller({
  required ImagePickerGateway picker,
  DetectionGateway? detector,
}) => StampController(
  picker: picker,
  detector: detector ?? _EmptyDetector(),
  exporter: (source, stamps) => Uint8List.fromList(<int>[1]),
  saver: _Saver(),
  history: _History(),
);

class _PickedImage extends PickedImage {
  const _PickedImage()
    : super(
        bytes: const <int>[1, 2, 3],
        name: 'test.png',
        imageSize: const PixelSize(100, 100),
      );
}

class _QueuePicker implements ImagePickerGateway {
  _QueuePicker(this.outcomes);

  final List<Object?> outcomes;

  @override
  Future<PickedImage?> pick() async {
    final outcome = outcomes.removeAt(0);
    if (outcome is Exception) throw outcome;
    return outcome as PickedImage?;
  }
}

class _EmptyDetector implements DetectionGateway {
  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) async =>
      const <DetectionRegion>[];
}

class _ThrowingDetector implements DetectionGateway {
  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) async =>
      throw StateError('detector internal failure');
}

class _Saver implements ImageSaverGateway {
  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async => true;
}

class _History implements ExportHistoryGateway {
  @override
  Future<int> readCount() async => 0;

  @override
  Future<void> recordExport() async {}
}
