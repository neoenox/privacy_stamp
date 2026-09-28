import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
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

/// No platform detector available (e.g. Web). Never throws, never detects.
class NoopFaceDetector implements FaceRegionDetector {
  const NoopFaceDetector();

  @override
  Future<DetectionResult> detect(Uint8ListImageInput input) async =>
      DetectionResult.empty();
}

/// On-device face detection via Google ML Kit (Android/iOS).
///
/// - Runs fully on-device; image bytes are never uploaded by this adapter.
/// - Detection runs on a downscaled oriented copy so a 40MP+ source does
///   not blow the heap. Returned boxes are mapped back through normalized
///   coordinates, which are resolution-independent.
/// - The copy is repacked to BGRA8888, the cross-platform format accepted
///   by ML Kit's `InputImage.fromBytes`. This eliminates the manual NV21
///   YUV conversion (see also: `_prepareImage` below).
/// - Uses ACCURATE mode with minFaceSize 0.05 for high-recall detection.
///   A lightweight FAST first pass at 1024px is used; if it returns zero
///   faces, a second ACCURATE pass runs at 1600-2048px to catch small faces
///   that the first pass may have missed.
/// - [DetectionOutcome] is surfaced so callers can distinguish "ML Kit ran
///   but found no faces" from "ML Kit failed entirely". See
///   [MlKitFaceDetector.detectionResult].
/// - Boxes are expanded by [paddingHorizontal]/[paddingVertical] so
///   hairline and chin edges stay covered.
class MlKitFaceDetector implements FaceRegionDetector {
  MlKitFaceDetector({
    this.firstPassMaxDimension = 1024,
    this.secondPassMaxDimension = 2048,
    this.minFaceSize = 0.05,
    this.paddingHorizontal = .02,
    this.paddingVertical = .03,
  });

  final int firstPassMaxDimension;
  final int secondPassMaxDimension;
  final double minFaceSize;
  final double paddingHorizontal;
  final double paddingVertical;

  /// Set by the last [detect] call. Use this to distinguish a real
  /// zero-face result from a detector failure.
  DetectionResult detectionResult = DetectionResult.empty();

  @override
  Future<DetectionResult> detect(Uint8ListImageInput input) async {
    if (kIsWeb) {
      detectionResult = DetectionResult.empty();
      return detectionResult;
    }
    try {
      final firstPass = await _detect(input, maxDimension: firstPassMaxDimension);

      if (firstPass.outcome == DetectionOutcome.success &&
          firstPass.regions.isNotEmpty) {
        detectionResult = firstPass;
        return detectionResult;
      }

      if (firstPass.outcome == DetectionOutcome.exception) {
        detectionResult = firstPass;
        return detectionResult;
      }

      final secondPass = await _detect(
        input,
        maxDimension: secondPassMaxDimension,
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: minFaceSize,
        ),
      );

      detectionResult = secondPass;
      return detectionResult;
    } catch (_) {
      detectionResult = DetectionResult.exception();
      return detectionResult;
    }
  }

  Future<DetectionResult> _detect(
    Uint8ListImageInput input, {
    required int maxDimension,
    FaceDetectorOptions? options,
  }) async {
    if (kIsWeb) return DetectionResult.empty();

    FaceDetector? detector;
    try {
      final prepared = await compute(
        _prepareImageWorker,
        _PrepareImagePayload(input, maxDimension),
      );
      if (prepared == null) return DetectionResult.empty();

      detector = FaceDetector(
        options: options ??
            FaceDetectorOptions(
              performanceMode: FaceDetectorMode.fast,
            ),
      );

      final mlKitInput = InputImage.fromBytes(
        bytes: prepared.bytes,
        metadata: InputImageMetadata(
          size: Size(prepared.width.toDouble(), prepared.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: prepared.bytesPerRow,
        ),
      );

      final faces = await detector.processImage(mlKitInput);
      final regions = <DetectionRegion>[];
      for (var i = 0; i < faces.length; i++) {
        final box = faces[i].boundingBox;
        final normalized = NormalizedRect(
          box.left / prepared.width,
          box.top / prepared.height,
          box.width / prepared.width,
          box.height / prepared.height,
        ).clamp().padded(paddingHorizontal, paddingVertical);
        if (!normalized.hasPositiveArea) continue;
        regions.add(
          DetectionRegion(
            id: 'face-$i',
            kind: DetectionKind.face,
            normalizedRect: normalized,
            reason: '顔の候補',
            sourceDetector: 'mlkit-face',
          ),
        );
      }
      return DetectionResult(
        regions: regions,
        outcome: regions.isEmpty
            ? DetectionOutcome.empty
            : DetectionOutcome.success,
        width: prepared.width,
        height: prepared.height,
        faceCount: faces.length,
      );
    } catch (e, st) {
      return DetectionResult.exception(
        error: e.toString(),
        stackTrace: st,
      );
    } finally {
      await detector?.close();
    }
  }
}

/// Decode, orient, downscale, and pack as BGRA8888 for ML Kit.
///
/// Using BGRA8888 instead of NV21:
/// - Eliminates the hand-written YUV conversion that was a fault point.
/// - Works identically on Android and iOS (BGRA is supported on both).
/// - The `image` package provides RGBA bytes directly; we reorder to
///   BGRA with `img.ChannelOrder.bgra`, which the package handles natively.
///
/// Even dimensions are required (odd edges are cropped by one pixel).
/// Returns `null` when the source cannot be decoded. Runs in a background
/// isolate via [compute]; keep this a top-level function.
_PreparedImage? _prepareImage(
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
    // BGRA needs even dimensions.
    var width = (sized.width ~/ 2) * 2;
    var height = (sized.height ~/ 2) * 2;
    if (width < 2 || height < 2) return null;
    if (width != sized.width || height != sized.height) {
      sized = img.copyResize(sized, width: width, height: height);
    }

    final bytes = sized.getBytes(order: img.ChannelOrder.bgra);
    return _PreparedImage(
      bytes: bytes,
      width: width,
      height: height,
      bytesPerRow: width * 4,
    );
  } catch (_) {
    return null;
  }
}

class _PrepareImagePayload {
  final Uint8ListImageInput input;
  final int maxDimension;

  _PrepareImagePayload(this.input, this.maxDimension);
}

_PreparedImage? _prepareImageWorker(_PrepareImagePayload payload) =>
    _prepareImage(payload.input, maxDimension: payload.maxDimension);
