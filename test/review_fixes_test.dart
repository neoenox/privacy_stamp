import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privacy_stamp/features/redaction/export/redaction_exporter.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';
import 'package:privacy_stamp/features/redaction/presentation/stamp_controller.dart';

void main() {
  group('review fixes', () {
    test('Stamp is immutable via copyWith', () {
      const stamp = Stamp(id: 'a', rect: NormalizedRect(.1, .1, .2, .2));
      final moved = stamp.copyWith(rect: const NormalizedRect(.2, .2, .2, .2));
      expect(stamp.rect.left, .1);
      expect(moved.rect.left, .2);
      expect(moved.id, 'a');
    });

    test('move replaces element without mutating old instance', () async {
      final controller = _Controller();
      await controller.pickImage();
      controller.addManualStamp();
      final before = controller.manualStamps.single;
      final beforeRect = before.rect;
      controller.moveManualStamp(before.id, const Offset(.1, 0));
      final after = controller.manualStamps.single;
      // Old instance keeps its rect (immutable model).
      expect(before.rect, beforeRect);
      expect(after.rect.left, greaterThan(beforeRect.left));
    });

    test('manual ids are unique under rapid adds', () async {
      final controller = _Controller();
      await controller.pickImage();
      for (var i = 0; i < 10; i++) {
        controller.addManualStamp();
      }
      final ids = controller.manualStamps.map((s) => s.id).toSet();
      expect(ids, hasLength(10));
    });

    test('sanitizeExportBasename blocks traversal', () {
      expect(sanitizeExportBasename(null), 'image');
      expect(sanitizeExportBasename(''), 'image');
      expect(sanitizeExportBasename('source.png'), 'source.png');
      expect(sanitizeExportBasename('../secret'), 'secret');
      expect(sanitizeExportBasename(r'..\..\win.ini'), 'win.ini');
      expect(sanitizeExportBasename('a/b/c.jpg'), 'c.jpg');
      expect(sanitizeExportBasename('...'), 'image');
    });

    test('export uses sanitized filename', () async {
      final saver = _RecordingSaver();
      final controller = _Controller(
        saver: saver,
        picker: const _TraversalPicker(),
      );
      await controller.pickImage();
      controller.addManualStamp();
      final result = await controller.exportImage();
      expect(result, ExportResult.exported);
      expect(saver.lastFileName, isNot(contains('..')));
      expect(saver.lastFileName, isNot(contains('/')));
      expect(saver.lastFileName, startsWith('privacy-stamped-'));
      expect(saver.lastFileName, endsWith('.png'));
    });

    test('export fails fast for oversized dimensions', () async {
      var exporterCalls = 0;
      final controller = StampController(
        picker: _HugePicker(),
        detector: const _Detector(),
        exporter: (source, stamps) async {
          exporterCalls++;
          return Uint8List.fromList([1]);
        },
        saver: _Saver(),
        history: const _History(),
      );
      await controller.pickImage();
      controller.addManualStamp();
      final result = await controller.exportImage();
      expect(result, ExportResult.failed);
      expect(exporterCalls, 0);
    });

    test('encoded PNG carries no privacy chunks', () {
      final sourceImage = img.Image(width: 8, height: 8);
      img.fill(sourceImage, color: img.ColorRgb8(10, 20, 30));
      final source = Uint8List.fromList(img.encodePng(sourceImage));
      final output = RedactionExporter().encode(source, [
        const Stamp(id: 'm', rect: NormalizedRect(.25, .25, .5, .5)),
      ]);
      final types = _chunkTypes(output);
      for (final forbidden in ['eXIf', 'tEXt', 'iTXt', 'zTXt', 'iCCP']) {
        expect(types, isNot(contains(forbidden)));
      }
    });
  });
}

List<String> _chunkTypes(Uint8List png) {
  final data = ByteData.sublistView(png);
  final types = <String>[];
  var offset = 33;
  while (offset + 8 <= png.lengthInBytes) {
    final length = data.getUint32(offset, Endian.big);
    final type = String.fromCharCodes(png.sublist(offset + 4, offset + 8));
    types.add(type);
    if (type == 'IEND') break;
    offset += 12 + length;
  }
  return types;
}

class _Controller extends StampController {
  _Controller({ImageSaverGateway? saver, ImagePickerGateway? picker})
    : super(
        picker: picker ?? const _Picker(),
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

class _TraversalPicker implements ImagePickerGateway {
  const _TraversalPicker();
  @override
  Future<PickedImage?> pick() async => const PickedImage(
    bytes: <int>[1, 2, 3],
    name: '../../secret photo?.png',
    imageSize: PixelSize(10, 10),
  );
}

class _HugePicker implements ImagePickerGateway {
  @override
  Future<PickedImage?> pick() async => PickedImage(
    bytes: const <int>[1, 2, 3],
    name: 'huge.jpg',
    // 100000x100000 exceeds the 64MP bound without allocating pixels.
    imageSize: const PixelSize(100000, 100000),
  );
}

class _Detector implements DetectionGateway {
  const _Detector();
  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) async =>
      const <DetectionRegion>[];
}

class _Saver implements ImageSaverGateway {
  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async => true;
}

class _RecordingSaver implements ImageSaverGateway {
  String? lastFileName;
  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async {
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
