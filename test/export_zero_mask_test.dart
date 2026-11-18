import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/stamp_controller.dart';
import 'package:privacy_stamp/main.dart';

void main() {
  group('Run C - export with zero masks', () {
    test('returns unavailable without calling saver', () async {
      final saver = _RecordingSaver();
      final controller = _Controller(saver: saver);
      await controller.pickImage();

      final result = await controller.exportImage();

      expect(result, ExportResult.unavailable);
      expect(saver.calls, 0);
      expect(controller.exportCount, 0);
    });

    testWidgets('shows unavailable guidance when no masks exist', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2400));

      final controller = _Controller();
      await tester.pumpWidget(
        PrivacyStampApp(home: StampHomePage(controller: controller)),
      );

      await controller.pickImage();
      await tester.pumpAndSettle();

      final exportButton = find.widgetWithText(FilledButton, '書き出す');
      expect(exportButton, findsOneWidget);

      await tester.tap(exportButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('隠す領域を追加してください'), findsOneWidget);
      expect(controller.exportCount, 0);
    });
  });
}

class _Controller extends StampController {
  _Controller({ImageSaverGateway? saver})
    : super(
        picker: const _Picker(),
        detector: const _Detector(),
        exporter: (source, stamps) => Uint8List.fromList(<int>[1]),
        saver: saver ?? _Saver(),
        history: const _History(),
      );
}

class _Picker implements ImagePickerGateway {
  const _Picker();

  @override
  Future<PickedImage?> pick() async => const PickedImage(
    bytes: <int>[1, 2, 3],
    name: 'source.png',
    imageSize: PixelSize(10, 10),
  );
}

class _Detector implements DetectionGateway {
  const _Detector();

  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) async =>
      const <DetectionRegion>[];
}

class _Saver implements ImageSaverGateway {
  const _Saver();

  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async => true;
}

class _RecordingSaver implements ImageSaverGateway {
  int calls = 0;
  Uint8List? lastBytes;
  String? lastFileName;

  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async {
    calls++;
    lastBytes = bytes;
    lastFileName = fileName;
    return true;
  }
}

class _History implements ExportHistoryGateway {
  const _History();

  @override
  Future<int> readCount() async => 0;

  @override
  Future<void> recordExport() async {}
}
