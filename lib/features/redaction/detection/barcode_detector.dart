import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image/image.dart' as img;

import '../models/redaction_models.dart';

class _PreparedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;

  _PreparedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
  });
}

/// No platform barcode scanner available (e.g. Web). Never throws.
class NoopCodeDetector implements CodeRegionDetector {
  const NoopCodeDetector();

  @override
  Future<List<DetectionRegion>> detect(Uint8ListImageInput input) async =>
      const [];
}

/// On-device barcode scanning via Google ML Kit (Android/iOS).
///
/// - Runs fully on-device; image bytes are never uploaded by this adapter.
/// - Scanning runs on a downscaled (max [maxDetectionDimension] px) oriented
///   copy so a 40MP+ source does not blow the heap. Boxes are mapped back
///   through normalized coordinates, which are resolution-independent.
/// - Every barcode value is treated as sensitive (URLs, identifiers, and
///   payment payloads routinely hide in QR/DataMatrix). Boxes are lightly
///   padded so quiet-zone edges stay covered.
class MlKitBarcodeDetector implements CodeRegionDetector {
  MlKitBarcodeDetector({
    this.formats = const [BarcodeFormat.all],
    this.maxDetectionDimension = 2048,
    this.paddingHorizontal = .01,
    this.paddingVertical = .015,
  });

  final List<BarcodeFormat> formats;
  final int maxDetectionDimension;
  final double paddingHorizontal;
  final double paddingVertical;

  @override
  Future<List<DetectionRegion>> detect(Uint8ListImageInput input) async {
    if (kIsWeb) return const [];
    try {
      final prepared = await compute(
        _prepareNv21ForBarcodeWorker,
        _PrepareBarcodePayload(input, maxDetectionDimension),
      );
      if (prepared == null) return const [];

      final mlKitInput = InputImage.fromBytes(
        bytes: prepared.bytes,
        metadata: InputImageMetadata(
          size: Size(prepared.width.toDouble(), prepared.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: prepared.bytesPerRow,
        ),
      );
      final scanner = BarcodeScanner(formats: formats);
      try {
        final barcodes = await scanner.processImage(mlKitInput);
        final regions = <DetectionRegion>[];
        for (var i = 0; i < barcodes.length; i++) {
          final box = barcodes[i].boundingBox;
          final normalized = NormalizedRect(
            box.left / prepared.width,
            box.top / prepared.height,
            box.width / prepared.width,
            box.height / prepared.height,
          ).clamp().padded(paddingHorizontal, paddingVertical);
          if (!normalized.hasPositiveArea) continue;
          regions.add(
            DetectionRegion(
              id: 'code-$i',
              kind: DetectionKind.code,
              normalizedRect: normalized,
              reason: 'バーコード (${barcodes[i].format.name})',
              sourceDetector: 'mlkit-barcode',
            ),
          );
        }
        return regions;
      } finally {
        await scanner.close();
      }
    } catch (_) {
      return const [];
    }
  }
}

/// Decode, orient, downscale, and repack as NV21 for ML Kit.
///
/// NV21 requires even dimensions; odd edges are cropped by one pixel.
/// Returns `null` when the source cannot be decoded.
_PreparedImage? _prepareNv21ForBarcode(
  Uint8ListImageInput input, {
  required int maxDimension,
}) {
  final source = input.bytes;
  try {
    if (source.isEmpty) return null;
    final decoded = img.decodeImage(Uint8List.fromList(source));
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    if (oriented.width <= 0 || oriented.height <= 0) return null;

    img.Image sized = oriented;
    final longest = oriented.width > oriented.height
        ? oriented.width
        : oriented.height;
    if (longest > maxDimension) {
      final scale = maxDimension / longest;
      sized = img.copyResize(
        oriented,
        width: (oriented.width * scale).round().clamp(1, maxDimension),
        height: (oriented.height * scale).round().clamp(1, maxDimension),
      );
    }
    var width = (sized.width ~/ 2) * 2;
    var height = (sized.height ~/ 2) * 2;
    if (width < 2 || height < 2) return null;
    if (width != sized.width || height != sized.height) {
      sized = img.copyResize(sized, width: width, height: height);
    }

    final rgba = sized.getBytes(order: img.ChannelOrder.rgba);
    final ySize = width * height;
    final nv21 = Uint8List(ySize + ySize ~/ 2);
    var yIndex = 0;
    // BT.601 integer approximation.
    for (var j = 0; j < height; j++) {
      for (var i = 0; i < width; i++) {
        final p = (j * width + i) * 4;
        final r = rgba[p];
        final g = rgba[p + 1];
        final b = rgba[p + 2];
        nv21[yIndex++] = (((66 * r + 129 * g + 25 * b + 128) >> 8) + 16)
            .clamp(0, 255);
        if (j.isEven && i.isEven) {
          final uvIndex = ySize + (j ~/ 2) * width + i;
          nv21[uvIndex] = (((112 * r - 94 * g - 18 * b + 128) >> 8) + 128)
              .clamp(0, 255);
          nv21[uvIndex + 1] = (((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128)
              .clamp(0, 255);
        }
      }
    }
    return _PreparedImage(
      bytes: nv21,
      width: width,
      height: height,
      bytesPerRow: width,
    );
  } catch (_) {
    return null;
  }
}

class _PrepareBarcodePayload {
  final Uint8ListImageInput input;
  final int maxDimension;

  _PrepareBarcodePayload(this.input, this.maxDimension);
}

_PreparedImage? _prepareNv21ForBarcodeWorker(_PrepareBarcodePayload payload) =>
    _prepareNv21ForBarcode(payload.input, maxDimension: payload.maxDimension);
