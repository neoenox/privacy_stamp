import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privacy_stamp/features/redaction/export/redaction_exporter.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/image_decode_policy.dart';

void main() {
  group('editorDecodeTarget', () {
    test('bounds a 48MP source by the physical editor viewport', () {
      final target = editorDecodeTarget(
        imageSize: const PixelSize(8000, 6000),
        canvasSize: const Size(640, 520),
        devicePixelRatio: 3,
      );

      expect(target.width, 2880);
      expect(target.height, 2160);
      expect(target.width * target.height, lessThan(8000 * 6000));
      expect(target.width, lessThanOrEqualTo(4096));
    });

    test('does not upscale small images', () {
      final target = editorDecodeTarget(
        imageSize: const PixelSize(320, 240),
        canvasSize: const Size(640, 520),
        devicePixelRatio: 3,
      );
      expect(target.width, 320);
      expect(target.height, 240);
    });

    test('handles invalid viewport values safely', () {
      final target = editorDecodeTarget(
        imageSize: const PixelSize(8000, 6000),
        canvasSize: const Size(double.infinity, double.nan),
        devicePixelRatio: double.infinity,
      );
      expect(target.width, 2);
      expect(target.height, 1);
    });
  });

  test(
    'lightweight inspection preserves JPEG orientation dimensions',
    () async {
      final source = img.encodeJpg(img.Image(width: 2, height: 3));
      final exif = img.ExifData()..imageIfd.orientation = 6;
      final orientedSource = img.injectJpgExif(source, exif);
      expect(orientedSource, isNotNull);

      final size = await const RedactionExporter().inspect(orientedSource!);
      expect(size.width, 3);
      expect(size.height, 2);
    },
  );

  test('inspection implementation never decodes a full frame', () {
    final source = File(
      'lib/features/redaction/export/redaction_exporter.dart',
    ).readAsStringSync();
    final start = source.indexOf('List<int> _inspectImage');
    final end = source.indexOf('Uint8List _encodeRedaction', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final inspection = source.substring(start, end);
    expect(inspection, contains('startDecode'));
    expect(inspection, isNot(contains('decodeFrame')));
    expect(inspection, isNot(contains('_decodeAndOrient')));
  });
}
