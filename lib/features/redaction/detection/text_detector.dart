import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import '../models/redaction_models.dart' as app;
import '../models/redaction_models.dart' show NormalizedRect;

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

/// No platform OCR available (e.g. Web). Never throws, never detects.
class NoopTextDetector implements app.TextRegionDetector {
  const NoopTextDetector();

  @override
  Future<List<app.RecognizedTextRegion>> detect(
    app.Uint8ListImageInput input,
  ) async =>
      const [];
}

/// On-device OCR via Google ML Kit Text Recognition (Android/iOS).
///
/// - Runs fully on-device; image bytes are never uploaded by this adapter.
/// - Detection runs on a downscaled (max [maxDetectionDimension] px) oriented
///   copy so a 40MP+ source does not blow the heap. Line boxes are mapped
///   back through normalized coordinates, which are resolution-independent.
/// - Default [script] is Japanese, which also recognizes Latin
///   alphanumerics commonly found in addresses and numbers. Pass
///   [TextRecognitionScript.latin] explicitly when only Latin is wanted.
class MlKitTextDetector implements app.TextRegionDetector {
  MlKitTextDetector({
    this.script = TextRecognitionScript.japanese,
    this.maxDetectionDimension = 2048,
  });

  final TextRecognitionScript script;
  final int maxDetectionDimension;

  @override
  Future<List<app.RecognizedTextRegion>> detect(
    app.Uint8ListImageInput input,
  ) async {
    if (kIsWeb) return const [];
    try {
      final prepared = await compute(
        _prepareNv21ForTextWorker,
        _PrepareTextPayload(input, maxDetectionDimension),
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
      final recognizer = TextRecognizer(script: script);
      try {
        final result = await recognizer.processImage(mlKitInput);
        final regions = <app.RecognizedTextRegion>[];
        for (final block in result.blocks) {
          for (final line in block.lines) {
            final text = line.text.trim();
            if (text.isEmpty) continue;
            final box = line.boundingBox;
            final normalized = NormalizedRect(
              box.left / prepared.width,
              box.top / prepared.height,
              box.width / prepared.width,
              box.height / prepared.height,
            ).clamp();
            if (!normalized.hasPositiveArea) continue;
            final confidence = (line.confidence ?? 1.0).clamp(0.0, 1.0);
            regions.add(
              app.RecognizedTextRegion(
                text: text,
                normalizedRect: normalized,
                confidence: confidence.toDouble(),
              ),
            );
          }
        }
        return regions;
      } finally {
        await recognizer.close();
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
_PreparedImage? _prepareNv21ForText(
  app.Uint8ListImageInput input, {
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

class _PrepareTextPayload {
  final app.Uint8ListImageInput input;
  final int maxDimension;

  _PrepareTextPayload(this.input, this.maxDimension);
}

_PreparedImage? _prepareNv21ForTextWorker(_PrepareTextPayload payload) =>
    _prepareNv21ForText(payload.input, maxDimension: payload.maxDimension);
