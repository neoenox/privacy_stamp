import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privacy_stamp/features/redaction/export/redaction_exporter.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/stamp_controller.dart';

import '../tool/acceptance/generate_synthetic_fixture.dart';
import '../tool/acceptance/image_metadata.dart';

void main() {
  group('Run D - JPEG metadata stripping', () {
    test('strips GPS EXIF from JPEG input', () async {
      final source = await generateSyntheticHighResolutionJpeg();
      final temp = await Directory.systemTemp.createTemp(
        'privacy-stamp-metadata-',
      );
      try {
        final inputPath = '${temp.path}${Platform.pathSeparator}input.jpg';
        await File(inputPath).writeAsBytes(source);

        final inputMetadata = await inspectAcceptanceImage(inputPath);
        expect(inputMetadata.gpsPresent, isTrue);

        final exporter = RedactionExporter();
        final output = exporter.encode(source, [
          Stamp(id: 'mask', rect: const NormalizedRect(.25, .25, .5, .5)),
        ]);

        final outputPath = '${temp.path}${Platform.pathSeparator}output.png';
        await File(outputPath).writeAsBytes(output);

        final outputMetadata = await inspectAcceptanceImage(outputPath);
        expect(outputMetadata.format, 'PNG');
        expect(outputMetadata.gpsPresent, isFalse);
        expect(outputMetadata.metadataContainerPresent, isFalse);
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('produces decodable PNG with preserved dimensions', () async {
      final source = await generateSyntheticHighResolutionJpeg();
      final exporter = RedactionExporter();
      final output = exporter.encode(source, [
        Stamp(id: 'mask', rect: const NormalizedRect(.25, .25, .5, .5)),
      ]);

      final decoded = img.decodePng(output);
      expect(decoded, isNotNull);
      expect(decoded!.width, 6000);
      expect(decoded.height, 8000);
    });

    test(
      'burns mask pixels into output and leaves unmasked pixels intact',
      () async {
        final source = await generateSyntheticHighResolutionJpeg();
        final exporter = RedactionExporter();

        final maskRect = const NormalizedRect(.4, .4, .2, .2);
        final output = exporter.encode(source, [
          Stamp(id: 'mask', rect: maskRect, kind: 'black'),
        ]);

        final decoded = img.decodePng(output)!;
        final layout = ImageDisplayLayout.contain(
          imageSize: const PixelSize(6000, 8000),
          canvasSize: const Size(6000, 8000),
        );

        final maskPixels = layout.pixelRectFromNormalized(maskRect);
        final centerX = maskPixels.left + maskPixels.width ~/ 2;
        final centerY = maskPixels.top + maskPixels.height ~/ 2;
        final maskPixel = decoded.getPixel(centerX, centerY);
        expect(maskPixel.r, 0);
        expect(maskPixel.g, 0);
        expect(maskPixel.b, 0);
        expect(maskPixel.a, 255);

        final outsidePixel = decoded.getPixel(100, 100);
        expect(outsidePixel.a, 255);
      },
    );

    test('does not modify source bytes', () async {
      final source = await generateSyntheticHighResolutionJpeg();
      final sourceHash = _sha256(source);

      final exporter = RedactionExporter();
      exporter.encode(source, [
        Stamp(id: 'mask', rect: const NormalizedRect(.25, .25, .5, .5)),
      ]);

      expect(_sha256(source), equals(sourceHash));
    });

    test(
      'output filename follows privacy-stamped-<original>.png rule',
      () async {
        final saver = _RecordingSaver();
        final controller = _Controller(saver: saver);
        await controller.pickImage();
        controller.addManualStamp();

        final result = await controller.exportImage();

        expect(result, ExportResult.exported);
        expect(saver.calls, 1);
        expect(saver.lastFileName, 'privacy-stamped-source.png.png');
      },
    );
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

List<int> _sha256(Uint8List bytes) {
  final digest = <int>[];
  for (var i = 0; i < bytes.length; i++) {
    digest.add(bytes[i]);
  }
  return digest;
}
