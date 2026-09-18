import 'dart:async';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../detection/barcode_detector.dart';
import '../detection/detector_service.dart';
import '../detection/face_detector.dart';
import '../detection/text_detector.dart';
import '../export/redaction_exporter.dart';
import '../models/redaction_models.dart';

typedef RedactionEncoder =
    FutureOr<Uint8List> Function(Uint8List source, List<Stamp> stamps);

abstract interface class ImagePickerGateway {
  Future<PickedImage?> pick();
}

abstract interface class ImageSaverGateway {
  Future<bool> save(Uint8List bytes, {required String fileName});
}

abstract interface class DetectionGateway {
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input);
}

abstract interface class ExportHistoryGateway {
  Future<int> readCount();
  Future<void> recordExport();
}

enum PickImageFailure { picker, decode, detection, detectionEmpty, detectionFailed }

enum PickImageResult {
  selected,
  cancelled,
  busy,
  stale,
  pickerFailed,
  decodeFailed,
  detectionFailed,
  detectionEmpty,
}

class ImagePickException implements Exception {
  const ImagePickException(this.failure);

  final PickImageFailure failure;
}

/// Strips directories, traversal sequences, and unsafe characters from the
/// original picker name so the export dialog cannot escape its target.
/// `source.png` -> `source.png`, `../secret` -> `secret`, empty -> `image`.
String sanitizeExportBasename(String? rawName) {
  if (rawName == null || rawName.trim().isEmpty) return 'image';
  var base = rawName.trim().replaceAll('\\', '/');
  base = base.split('/').last;
  base = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  base = base.replaceAll(RegExp(r'_+'), '_');
  base = base.replaceAll(RegExp(r'^[.]+'), '');
  if (base.isEmpty || base == '.' || base == '..') return 'image';
  if (base.length > 80) base = base.substring(0, 80);
  return base;
}

class PickedImage {
  const PickedImage({
    required this.bytes,
    required this.name,
    required this.imageSize,
  });

  final List<int> bytes;
  final String name;
  final PixelSize imageSize;
}

class FilePickerImageGateway implements ImagePickerGateway {
  const FilePickerImageGateway({this.inspector = const RedactionExporter()});

  final RedactionExporter inspector;

  @override
  Future<PickedImage?> pick() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
    } catch (_) {
      throw const ImagePickException(PickImageFailure.picker);
    }

    final file = result?.files.single;
    if (file == null) return null;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const ImagePickException(PickImageFailure.decode);
    }

    try {
      final imageSize = await inspector.inspect(bytes);
      return PickedImage(bytes: bytes, name: file.name, imageSize: imageSize);
    } catch (_) {
      throw const ImagePickException(PickImageFailure.decode);
    }
  }
}

class FilePickerImageSaver implements ImageSaverGateway {
  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async =>
      await FilePicker.platform.saveFile(fileName: fileName, bytes: bytes) !=
      null;
}

class DetectionServiceGateway implements DetectionGateway {
  DetectionServiceGateway({DetectionService? detector})
    : _detector = detector ?? DetectionService();

  final DetectionService _detector;

  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) =>
      _detector.inspect(input);

  /// Diagnostic information from the most recent [inspect] call.
  DetectionSummary? get lastSummary => _detector.lastSummary;
}

class SharedPreferencesExportHistory implements ExportHistoryGateway {
  static const _key = 'export_count';

  @override
  Future<int> readCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? 0;
  }

  @override
  Future<void> recordExport() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setInt(_key, (prefs.getInt(_key) ?? 0) + 1);
    if (!saved) throw StateError('書き出し履歴を保存できませんでした');
  }
}

enum ExportResult { exported, cancelled, unavailable, busy, failed, stale }

/// Application build identifier. Updated at each release build.
const String appBuildSha = 'development';
const String appBuildVersion = '1.0.0+5';

class StampController extends ChangeNotifier {
  StampController({
    required this.picker,
    required this.detector,
    required this.exporter,
    required this.saver,
    required this.history,
  }) {
    _loadHistory();
  }

  factory StampController.defaults() => StampController(
    picker: const FilePickerImageGateway(),
    detector: DetectionServiceGateway(
      detector: DetectionService(
        faceDetector: MlKitFaceDetector(),
        textDetector: MlKitTextDetector(),
        codeDetector: MlKitBarcodeDetector(),
      ),
    ),
    exporter: const RedactionExporter().encodeAsync,
    saver: FilePickerImageSaver(),
    history: SharedPreferencesExportHistory(),
  );

  factory StampController.testInstance() => StampController(
    picker: const _TestImagePickerGateway(),
    detector: _TestDetectionGateway(),
    exporter: const RedactionExporter().encodeAsync,
    saver: const _TestImageSaverGateway(),
    history: SharedPreferencesExportHistory(),
  );

  @visibleForTesting
  void loadImageForTesting(Uint8List bytes, String name, PixelSize imageSize) {
    if (_disposed) return;
    _bytes = bytes;
    _fileName = name;
    _imageSize = imageSize;
    _detections = const [];
    _manualStamps = const [];
    _manualUndoSnapshot = null;
    _pickFailure = null;
    _busy = false;
    _lastDetectionSummary = null;
    notifyListeners();
  }

  final ImagePickerGateway picker;
  final DetectionGateway detector;
  final RedactionEncoder exporter;
  final ImageSaverGateway saver;
  final ExportHistoryGateway history;

  Uint8List? _bytes;
  String? _fileName;
  PixelSize? _imageSize;
  List<DetectionRegion> _detections = const [];
  List<Stamp> _manualStamps = const [];
  List<Stamp>? _manualUndoSnapshot;
  PickImageFailure? _pickFailure;
  bool _busy = false;
  bool _disposed = false;
  int _generation = 0;
  int _exportCount = 0;
  int _manualIdSeq = 0;
  DetectionSummary? _lastDetectionSummary;

  Uint8List? get bytes => _bytes;
  String? get fileName => _fileName;
  PixelSize? get imageSize => _imageSize;
  bool get hasImage => _bytes != null;
  bool get isBusy => _busy;
  bool get canUndoManualEdit => _manualUndoSnapshot != null;
  int get exportCount => _exportCount;
  PickImageFailure? get pickFailure => _pickFailure;
  List<DetectionRegion> get detections => List.unmodifiable(_detections);
  DetectionSummary? get lastDetectionSummary => _lastDetectionSummary;
  int get automaticCount =>
      _detections.where((detection) => detection.isEnabled).length;
  List<Stamp> get manualStamps => List.unmodifiable(_manualStamps);
  List<Stamp> get stamps => [
    for (final detection in _detections)
      if (detection.isEnabled)
        Stamp(
          id: detection.id,
          rect: detection.normalizedRect,
          isAutomatic: true,
        ),
    ..._manualStamps,
  ];

  Future<void> _loadHistory() async {
    try {
      final count = await history.readCount();
      if (_disposed) return;
      _exportCount = count;
      notifyListeners();
    } catch (_) {
      // History is informational only. A storage failure must not block editing.
    }
  }

  Future<PickImageResult> pickImage() async {
    if (_disposed) return PickImageResult.stale;
    if (_busy) return PickImageResult.busy;

    final token = ++_generation;
    _pickFailure = null;
    _busy = true;
    _lastDetectionSummary = null;
    notifyListeners();

    try {
      final PickedImage? picked;
      try {
        picked = await picker.pick();
      } on ImagePickException catch (error) {
        if (!_isCurrent(token)) return PickImageResult.stale;
        _pickFailure = error.failure;
        return _resultForFailure(error.failure);
      } catch (_) {
        if (!_isCurrent(token)) return PickImageResult.stale;
        _pickFailure = PickImageFailure.picker;
        return PickImageResult.pickerFailed;
      }

      if (!_isCurrent(token)) return PickImageResult.stale;
      if (picked == null) return PickImageResult.cancelled;

      _bytes = picked.bytes is Uint8List
          ? picked.bytes as Uint8List
          : Uint8List.fromList(picked.bytes);
      _fileName = picked.name;
      _imageSize = picked.imageSize;
      _detections = const [];
      _manualStamps = const [];
      _manualUndoSnapshot = null;
      notifyListeners();

      try {
        final regions = await detector.inspect(Uint8ListImageInput(_bytes!));
        if (!_isCurrent(token)) return PickImageResult.stale;
        if (detector is DetectionServiceGateway) {
          _lastDetectionSummary = (detector as DetectionServiceGateway).lastSummary;
        }
        _detections = List.unmodifiable(regions);
        _pickFailure = null;

        if (_detections.isEmpty) {
          return PickImageResult.detectionEmpty;
        }
        return PickImageResult.selected;
      } catch (_) {
        if (!_isCurrent(token)) return PickImageResult.stale;
        // The selected image remains editable. Automatic suggestions are an
        // optional enhancement and must not discard a valid local image.
        _detections = const [];
        _pickFailure = PickImageFailure.detectionFailed;
        return PickImageResult.detectionFailed;
      }
    } finally {
      if (_isCurrent(token)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  PickImageResult _resultForFailure(PickImageFailure failure) =>
      switch (failure) {
        PickImageFailure.picker => PickImageResult.pickerFailed,
        PickImageFailure.decode => PickImageResult.decodeFailed,
        PickImageFailure.detection => PickImageResult.detectionFailed,
        PickImageFailure.detectionEmpty => PickImageResult.detectionEmpty,
        PickImageFailure.detectionFailed => PickImageResult.detectionFailed,
      };

  void addManualStamp() => addManualStampAt(const Offset(.5, .5));

  void addManualStampAt(Offset normalizedCenter) {
    if (_disposed || _busy || !hasImage) return;
    const width = .3;
    const height = .16;
    final rect = NormalizedRect(
      normalizedCenter.dx - width / 2,
      normalizedCenter.dy - height / 2,
      width,
      height,
    ).clamp();
    _rememberManualState();
    _manualStamps = [..._manualStamps, Stamp(id: _nextManualId(), rect: rect)];
    notifyListeners();
  }

  void moveManualStamp(String id, Offset delta) {
    if (_disposed || _busy) return;
    final index = _manualIndexOf(id);
    if (index < 0) return;
    final rect = _manualStamps[index].rect;
    final next = NormalizedRect(
      (rect.left + delta.dx).clamp(0.0, 1.0 - rect.width).toDouble(),
      (rect.top + delta.dy).clamp(0.0, 1.0 - rect.height).toDouble(),
      rect.width,
      rect.height,
    );
    if (next == rect) return;
    _rememberManualState();
    _manualStamps = [
      for (var i = 0; i < _manualStamps.length; i++)
        if (i == index)
          _manualStamps[i].copyWith(rect: next)
        else
          _manualStamps[i],
    ];
    notifyListeners();
  }

  void resizeManualStamp(String id, Offset delta) {
    if (_disposed || _busy) return;
    final index = _manualIndexOf(id);
    if (index < 0) return;
    final rect = _manualStamps[index].rect;
    final width = (rect.width + delta.dx)
        .clamp(.05, 1.0 - rect.left)
        .toDouble();
    final height = (rect.height + delta.dy)
        .clamp(.04, 1.0 - rect.top)
        .toDouble();
    final next = NormalizedRect(rect.left, rect.top, width, height);
    if (next == rect) return;
    _rememberManualState();
    _manualStamps = [
      for (var i = 0; i < _manualStamps.length; i++)
        if (i == index)
          _manualStamps[i].copyWith(rect: next)
        else
          _manualStamps[i],
    ];
    notifyListeners();
  }

  void removeManualStamp(String id) {
    if (_disposed || _busy) return;
    if (_manualIndexOf(id) < 0) return;
    _rememberManualState();
    _manualStamps = _manualStamps.where((stamp) => stamp.id != id).toList();
    notifyListeners();
  }

  void undoManualEdit() {
    if (_disposed || _busy) return;
    final snapshot = _manualUndoSnapshot;
    if (snapshot == null) return;
    _manualStamps = _copyManualStamps(snapshot);
    _manualUndoSnapshot = null;
    notifyListeners();
  }

  /// Disables all automatic suggestions (e.g. face candidates the user
  /// rejected). Manual stamps are untouched. Export then covers only the
  /// remaining enabled regions plus manual stamps.
  void clearAutomaticDetections() {
    if (_disposed || _busy) return;
    if (_detections.isEmpty) return;
    var changed = false;
    for (final detection in _detections) {
      if (detection.isEnabled) {
        detection.isEnabled = false;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void reset() {
    if (_disposed) return;
    ++_generation;
    _bytes = null;
    _fileName = null;
    _imageSize = null;
    _detections = const [];
    _manualStamps = const [];
    _manualUndoSnapshot = null;
    _pickFailure = null;
    _busy = false;
    _lastDetectionSummary = null;
    notifyListeners();
  }

  Future<ExportResult> exportImage() async {
    if (_disposed) return ExportResult.stale;
    if (_busy) return ExportResult.busy;
    final bytes = _bytes;
    final stamps = this.stamps;
    final imageSize = _imageSize;
    if (bytes == null || stamps.isEmpty || imageSize == null) {
      return ExportResult.unavailable;
    }
    // Fail fast before allocating a full-res pixel buffer on low-memory
    // devices. The exporter re-validates the same bound after decode.
    if (imageSize.width <= 0 ||
        imageSize.height <= 0 ||
        imageSize.width >
            const RedactionExporter().maxPixels ~/ imageSize.height) {
      return ExportResult.failed;
    }

    final token = _generation;
    _busy = true;
    notifyListeners();
    try {
      final output = await exporter(bytes, stamps);
      final saved = await saver.save(
        output,
        fileName:
            'privacy-stamped-${sanitizeExportBasename(_fileName)}.png',
      );
      if (!_isCurrent(token)) return ExportResult.stale;
      if (!saved) return ExportResult.cancelled;

      var historyPersisted = false;
      try {
        await history.recordExport();
        historyPersisted = true;
      } catch (_) {
        // The image save succeeded. History remains unchanged when persistence
        // fails so the displayed count cannot roll back after restart.
      }
      if (!_isCurrent(token)) return ExportResult.stale;
      if (historyPersisted) _exportCount++;
      return ExportResult.exported;
    } catch (_) {
      return ExportResult.failed;
    } finally {
      if (_isCurrent(token)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  void _rememberManualState() {
    _manualUndoSnapshot = _copyManualStamps(_manualStamps);
  }

  List<Stamp> _copyManualStamps(Iterable<Stamp> source) => [
    for (final stamp in source)
      Stamp(
        id: stamp.id,
        rect: stamp.rect,
        kind: stamp.kind,
        isAutomatic: stamp.isAutomatic,
      ),
  ];

  int _manualIndexOf(String id) {
    for (var i = 0; i < _manualStamps.length; i++) {
      if (_manualStamps[i].id == id) return i;
    }
    return -1;
  }

  String _nextManualId() =>
      'manual-${DateTime.now().microsecondsSinceEpoch}-${_manualIdSeq++}';

  bool _isCurrent(int token) => !_disposed && token == _generation;

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}

class _TestImagePickerGateway implements ImagePickerGateway {
  const _TestImagePickerGateway();

  @override
  Future<PickedImage?> pick() async => null;
}

class _TestImageSaverGateway implements ImageSaverGateway {
  const _TestImageSaverGateway();

  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async => true;
}

class _TestDetectionGateway implements DetectionGateway {
  const _TestDetectionGateway();

  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) async =>
      const [];
}
