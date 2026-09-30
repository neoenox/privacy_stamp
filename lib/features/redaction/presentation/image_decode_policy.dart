import 'dart:math' as math;
import 'dart:ui';

import '../models/redaction_models.dart';

class DecodeTarget {
  const DecodeTarget(this.width, this.height);

  final int width;
  final int height;
}

/// Bounds editor decoding by the physical viewport and a hard safety ceiling.
///
/// A small overscan keeps moderate zoom crisp without decoding the full source
/// image. The source aspect ratio is preserved and small images are not
/// upscaled.
DecodeTarget editorDecodeTarget({
  required PixelSize imageSize,
  required Size canvasSize,
  required double devicePixelRatio,
  double overscan = 1.5,
  // Keep the editor texture bounded on low-memory devices. Export still uses
  // the original bytes; this limit applies only to the interactive preview.
  int maxDimension = 1024,
}) {
  if (imageSize.width <= 0 || imageSize.height <= 0) {
    throw ArgumentError('Image dimensions must be positive');
  }
  if (maxDimension <= 0 || overscan <= 0 || !overscan.isFinite) {
    throw ArgumentError('Invalid decode policy');
  }

  final canvasWidth = canvasSize.width.isFinite
      ? math.max(1.0, canvasSize.width)
      : 1.0;
  final canvasHeight = canvasSize.height.isFinite
      ? math.max(1.0, canvasSize.height)
      : 1.0;
  final dpr = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 1.0;
  final sourceWidth = imageSize.width.toDouble();
  final sourceHeight = imageSize.height.toDouble();

  final scale = math.min(
    1.0,
    math.min(
      maxDimension / math.max(sourceWidth, sourceHeight),
      math.min(
        canvasWidth * dpr * overscan / sourceWidth,
        canvasHeight * dpr * overscan / sourceHeight,
      ),
    ),
  );

  return DecodeTarget(
    math.max(1, (sourceWidth * scale).round()),
    math.max(1, (sourceHeight * scale).round()),
  );
}
