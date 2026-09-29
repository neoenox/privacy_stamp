import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../tool/acceptance/image_metadata.dart';
import '../tool/acceptance/generate_synthetic_fixture.dart';

void main() {
  test('generates a deterministic synthetic JPEG with GPS metadata', () async {
    final first = await generateSyntheticHighResolutionJpeg();
    final second = await generateSyntheticHighResolutionJpeg();

    expect(first, equals(second));

    final temp = await Directory.systemTemp.createTemp(
      'privacy-stamp-synthetic-',
    );
    try {
      final path = '${temp.path}${Platform.pathSeparator}synthetic.jpg';
      await File(path).writeAsBytes(first);

      final metadata = await inspectAcceptanceImage(path);

      expect(metadata.format, 'JPEG');
      expect(metadata.pixels, greaterThanOrEqualTo(40000000));
      expect(metadata.gpsPresent, isTrue);
      expect(metadata.width, 6000);
      expect(metadata.height, 8000);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('injects GPS EXIF into the synthetic JPEG', () async {
    final bytes = await generateSyntheticHighResolutionJpeg();
    final exif = image.decodeJpgExif(bytes);
    expect(exif, isNotNull);
    expect(exif!.gpsIfd.gpsLatitudeRef, 'N');
    expect(exif.gpsIfd.gpsLatitude, greaterThan(0));
    expect(exif.gpsIfd.gpsLongitudeRef, 'E');
    expect(exif.gpsIfd.gpsLongitude, greaterThan(0));
  });

  test('generates at least 40MP', () async {
    final bytes = await generateSyntheticHighResolutionJpeg();
    expect(bytes.length, greaterThan(0));
  });
}
