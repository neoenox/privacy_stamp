import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/redaction_models.dart';

class RedactionExporter {
  const RedactionExporter({
    this.maxSourceBytes = 64 * 1024 * 1024,
    this.maxPixels = 64 * 1000 * 1000,
  });

  final int maxSourceBytes;
  final int maxPixels;

  /// Reads the orientation-corrected dimensions without blocking the UI
  /// isolate on native platforms. The same callback remains Web-compatible.
  Future<PixelSize> inspect(Uint8List source) async {
    final dimensions = await compute(_inspectImage, <String, Object>{
      'source': source,
      'maxSourceBytes': maxSourceBytes,
      'maxPixels': maxPixels,
    });
    return PixelSize(dimensions[0], dimensions[1]);
  }

  /// Encodes in a background isolate on native platforms.
  Future<Uint8List> encodeAsync(Uint8List source, List<Stamp> stamps) =>
      compute(_encodeRedaction, _payload(source, stamps));

  /// Synchronous entry point retained for deterministic unit tests.
  Uint8List encode(Uint8List source, List<Stamp> stamps) =>
      _encodeRedaction(_payload(source, stamps));

  Map<String, Object> _payload(Uint8List source, List<Stamp> stamps) =>
      <String, Object>{
        'source': source,
        'maxSourceBytes': maxSourceBytes,
        'maxPixels': maxPixels,
        'masks': <Object>[
          for (final stamp in stamps)
            <String, Object>{
              'left': stamp.rect.left,
              'top': stamp.rect.top,
              'width': stamp.rect.width,
              'height': stamp.rect.height,
              'kind': stamp.kind,
            },
        ],
      };
}

List<int> _inspectImage(Map<String, Object> payload) {
  final source = payload['source']! as Uint8List;
  final maxSourceBytes = payload['maxSourceBytes']! as int;
  final maxPixels = payload['maxPixels']! as int;
  if (source.isEmpty) throw const FormatException('画像データが空です');
  if (source.lengthInBytes > maxSourceBytes) {
    throw const FormatException('画像ファイルが大きすぎます');
  }

  try {
    final decoder = img.findDecoderForData(source);
    if (decoder == null || !decoder.isValidFile(source)) {
      throw const FormatException('画像を読み込めませんでした');
    }
    final info = decoder.startDecode(source);
    if (info == null || info.numFrames < 1) {
      throw const FormatException('画像を読み込めませんでした');
    }
    _validateDimensions(info.width, info.height, maxPixels: maxPixels);

    var width = info.width;
    var height = info.height;
    final orientation = img.decodeJpgExif(source)?.imageIfd.orientation;
    if (orientation == 5 ||
        orientation == 6 ||
        orientation == 7 ||
        orientation == 8) {
      final originalWidth = width;
      width = height;
      height = originalWidth;
    }
    _validateDimensions(width, height, maxPixels: maxPixels);
    return <int>[width, height];
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('画像を読み込めませんでした');
  }
}

Uint8List _encodeRedaction(Map<String, Object> payload) {
  final oriented = _decodeAndOrient(
    payload['source']! as Uint8List,
    maxSourceBytes: payload['maxSourceBytes']! as int,
    maxPixels: payload['maxPixels']! as int,
  );

  // The output is a fresh privacy boundary. Do not carry EXIF, ICC, or
  // textual/XMP metadata from the decoded input into the PNG encoder.
  oriented.exif = img.ExifData();
  oriented.iccProfile = null;
  oriented.textData = null;

  final layout = ImageDisplayLayout.contain(
    imageSize: PixelSize(oriented.width, oriented.height),
    canvasSize: Size(oriented.width.toDouble(), oriented.height.toDouble()),
  );

  final masks = payload['masks']! as List<Object>;
  for (final rawMask in masks) {
    final mask = rawMask as Map<Object?, Object?>;
    final rect = NormalizedRect(
      mask['left']! as double,
      mask['top']! as double,
      mask['width']! as double,
      mask['height']! as double,
    );
    final pixels = layout.pixelRectFromNormalized(rect);
    final color = switch (mask['kind']! as String) {
      'white' => img.ColorRgb8(255, 255, 255),
      'black' => img.ColorRgb8(0, 0, 0),
      final kind => throw FormatException('未対応のマスク色です: $kind'),
    };
    img.fillRect(
      oriented,
      x1: pixels.left,
      y1: pixels.top,
      x2: pixels.right - 1,
      y2: pixels.bottom - 1,
      color: color,
    );
  }

  // Large 48MP exports must complete inside the low-memory acceptance wall
  // clock. A filter-free, level-0 PNG avoids the CPU-heavy Paeth/zlib path
  // while preserving the same lossless pixels and metadata-free boundary.
  final output = img.PngEncoder(
    filter: img.PngFilter.none,
    level: 0,
  ).encode(oriented);
  _validatePngHeader(
    output,
    expectedWidth: oriented.width,
    expectedHeight: oriented.height,
  );
  return output;
}

img.Image _decodeAndOrient(
  Uint8List source, {
  required int maxSourceBytes,
  required int maxPixels,
}) {
  if (source.isEmpty) throw const FormatException('画像データが空です');
  if (source.lengthInBytes > maxSourceBytes) {
    throw const FormatException('画像ファイルが大きすぎます');
  }

  try {
    final decoder = img.findDecoderForData(source);
    if (decoder == null) {
      throw const FormatException('画像を読み込めませんでした');
    }
    final info = decoder.startDecode(source);
    if (info == null) {
      throw const FormatException('画像を読み込めませんでした');
    }

    // Reject decompression bombs before allocating the full pixel buffer.
    _validateDimensions(info.width, info.height, maxPixels: maxPixels);
    final decoded = decoder.decodeFrame(0);
    if (decoded == null) {
      throw const FormatException('画像を読み込めませんでした');
    }

    final oriented = img.bakeOrientation(decoded);
    _validateDimensions(oriented.width, oriented.height, maxPixels: maxPixels);
    return oriented;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('画像を読み込めませんでした');
  }
}

void _validateDimensions(int width, int height, {required int maxPixels}) {
  if (width <= 0 || height <= 0) {
    throw const FormatException('画像サイズが0pxです');
  }
  if (width > maxPixels ~/ height) {
    throw const FormatException('画像の画素数が大きすぎます');
  }
}

void _validatePngHeader(
  Uint8List output, {
  required int expectedWidth,
  required int expectedHeight,
}) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (output.lengthInBytes < 24) {
    throw const FormatException('PNGを書き出せませんでした');
  }
  for (var index = 0; index < signature.length; index++) {
    if (output[index] != signature[index]) {
      throw const FormatException('PNGを書き出せませんでした');
    }
  }
  if (output[12] != 73 ||
      output[13] != 72 ||
      output[14] != 68 ||
      output[15] != 82) {
    throw const FormatException('PNGを書き出せませんでした');
  }

  final header = ByteData.sublistView(output);
  final width = header.getUint32(16, Endian.big);
  final height = header.getUint32(20, Endian.big);
  if (width != expectedWidth || height != expectedHeight) {
    throw const FormatException('PNGを書き出せませんでした');
  }
}
