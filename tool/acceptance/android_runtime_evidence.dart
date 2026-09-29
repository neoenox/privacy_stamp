import 'dart:math' as math;

final class AcceptanceMemorySample {
  const AcceptanceMemorySample({
    required this.pid,
    required this.totalPssKb,
    required this.totalRssKb,
    required this.javaHeapKb,
    required this.nativeHeapKb,
  });

  final int pid;
  final int totalPssKb;
  final int? totalRssKb;
  final int? javaHeapKb;
  final int? nativeHeapKb;

  Map<String, Object?> toJson() => <String, Object?>{
    'pid': pid,
    'totalPssKb': totalPssKb,
    'totalRssKb': totalRssKb,
    'javaHeapKb': javaHeapKb,
    'nativeHeapKb': nativeHeapKb,
  };
}

AcceptanceMemorySample parseDumpsysMeminfo(String text, {int? expectedPid}) {
  final headerPid = RegExp(
    r'\*\*\s+MEMINFO\s+in\s+pid\s+(\d+)',
  ).firstMatch(text);
  final observedPid = int.tryParse(headerPid?.group(1) ?? '');
  if (expectedPid != null &&
      observedPid != null &&
      expectedPid != observedPid) {
    throw const FormatException('The meminfo process ID changed.');
  }
  final pid = expectedPid ?? observedPid;
  if (pid == null || pid <= 0) {
    throw const FormatException('A valid app process ID is required.');
  }

  final lines = text.split(RegExp(r'\r?\n'));
  int? totalPssKb;
  int? totalRssKb;
  int? javaHeapKb;
  int? nativeHeapKb;
  var inAppSummary = false;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line == 'App Summary') {
      inAppSummary = true;
      continue;
    }
    if (!inAppSummary) continue;

    final parsed = _parseSummaryLine(line);
    if (parsed == null) continue;
    final (label, firstValue, lastValue) = parsed;
    switch (label) {
      case 'Java Heap':
        javaHeapKb = firstValue;
        break;
      case 'Native Heap':
        nativeHeapKb = firstValue;
        break;
      case 'TOTAL':
        totalPssKb = firstValue;
        totalRssKb = lastValue;
        break;
    }
  }

  // Older Android versions may omit the App Summary table. In that case,
  // accept the first TOTAL row as PSS only, but never invent an RSS value.
  if (totalPssKb == null) {
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (!RegExp(r'^TOTAL(?:\s|:)').hasMatch(line)) continue;
      final numbers = _numbers(line);
      if (numbers.isNotEmpty) {
        totalPssKb = numbers.first;
        break;
      }
    }
  }

  if (totalPssKb == null) {
    throw const FormatException('TOTAL PSS was not present in meminfo.');
  }

  return AcceptanceMemorySample(
    pid: pid,
    totalPssKb: totalPssKb,
    totalRssKb: totalRssKb,
    javaHeapKb: javaHeapKb,
    nativeHeapKb: nativeHeapKb,
  );
}

(String, int, int?)? _parseSummaryLine(String line) {
  final match = RegExp(
    r'^(Java Heap|Native Heap|TOTAL):?\s+(.+)$',
  ).firstMatch(line);
  if (match == null) return null;
  final values = _numbers(match.group(2)!);
  if (values.isEmpty) return null;
  final lastValue = values.length > 1 ? values.last : null;
  return (match.group(1)!, values.first, lastValue);
}

List<int> _numbers(String value) {
  return RegExp(r'\d[\d,]*')
      .allMatches(value)
      .map((match) => int.parse(match.group(0)!.replaceAll(',', '')))
      .toList(growable: false);
}

enum AcceptanceRuntimeEventType {
  fatalException,
  anr,
  outOfMemory,
  fatalSignal,
  processDeath,
  lowMemoryKill,
}

final class AcceptanceRuntimeSummary {
  const AcceptanceRuntimeSummary({
    required this.sampleCount,
    required this.peakTotalPssKb,
    required this.peakTotalRssKb,
    required this.peakJavaHeapKb,
    required this.peakNativeHeapKb,
    required this.processRestartCount,
    required this.processAliveAfterExport,
    required this.events,
  });

  factory AcceptanceRuntimeSummary.fromEvidence({
    required List<AcceptanceMemorySample> samples,
    required String logcat,
    required String packageName,
    required bool processAliveAfterExport,
  }) {
    if (samples.isEmpty) {
      throw const FormatException('At least one memory sample is required.');
    }
    if (packageName.trim().isEmpty) {
      throw const FormatException('A package name is required.');
    }

    final pids = samples.map((sample) => sample.pid).toSet();
    final events = parseRuntimeEvents(
      logcat,
      packageName: packageName,
      monitoredPids: pids,
    );

    var peakPss = 0;
    int? peakRss;
    int? peakJava;
    int? peakNative;
    var restartCount = 0;
    int? previousPid;
    for (final sample in samples) {
      peakPss = math.max(peakPss, sample.totalPssKb);
      peakRss = _maxNullable(peakRss, sample.totalRssKb);
      peakJava = _maxNullable(peakJava, sample.javaHeapKb);
      peakNative = _maxNullable(peakNative, sample.nativeHeapKb);
      if (previousPid != null && previousPid != sample.pid) {
        restartCount += 1;
      }
      previousPid = sample.pid;
    }

    return AcceptanceRuntimeSummary(
      sampleCount: samples.length,
      peakTotalPssKb: peakPss,
      peakTotalRssKb: peakRss,
      peakJavaHeapKb: peakJava,
      peakNativeHeapKb: peakNative,
      processRestartCount: restartCount,
      processAliveAfterExport: processAliveAfterExport,
      events: events,
    );
  }

  final int sampleCount;
  final int peakTotalPssKb;
  final int? peakTotalRssKb;
  final int? peakJavaHeapKb;
  final int? peakNativeHeapKb;
  final int processRestartCount;
  final bool processAliveAfterExport;
  final Set<AcceptanceRuntimeEventType> events;

  bool get passed =>
      sampleCount > 0 &&
      processRestartCount == 0 &&
      processAliveAfterExport &&
      events.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'sampleCount': sampleCount,
    'peakTotalPssKb': peakTotalPssKb,
    'peakTotalRssKb': peakTotalRssKb,
    'peakJavaHeapKb': peakJavaHeapKb,
    'peakNativeHeapKb': peakNativeHeapKb,
    'processRestartCount': processRestartCount,
    'processAliveAfterExport': processAliveAfterExport,
    'events': _sortedEventNames(),
    'passed': passed,
  };

  List<String> _sortedEventNames() {
    final names = events.map((event) => event.name).toList(growable: false);
    names.sort();
    return names;
  }
}

int? _maxNullable(int? current, int? candidate) {
  if (candidate == null) return current;
  if (current == null) return candidate;
  return math.max(current, candidate);
}

Set<AcceptanceRuntimeEventType> parseRuntimeEvents(
  String logcat, {
  required String packageName,
  required Set<int> monitoredPids,
}) {
  final events = <AcceptanceRuntimeEventType>{};
  for (final rawLine in logcat.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final lower = line.toLowerCase();
    final belongsToPackage = lower.contains(packageName.toLowerCase());
    final linePid = _threadtimePid(line);
    final belongsToPid = linePid != null && monitoredPids.contains(linePid);
    final belongsToProcess = belongsToPackage || belongsToPid;

    if (belongsToProcess && lower.contains('fatal exception')) {
      events.add(AcceptanceRuntimeEventType.fatalException);
    }
    if (belongsToProcess && lower.contains('outofmemoryerror')) {
      events.add(AcceptanceRuntimeEventType.outOfMemory);
    }
    if (belongsToProcess && lower.contains('fatal signal')) {
      events.add(AcceptanceRuntimeEventType.fatalSignal);
    }
    if (belongsToPackage &&
        (lower.contains('anr in ') || lower.contains('not responding'))) {
      events.add(AcceptanceRuntimeEventType.anr);
    }
    if (belongsToPackage &&
        (lower.contains('has died') || lower.contains('process died'))) {
      events.add(AcceptanceRuntimeEventType.processDeath);
    }
    if (belongsToProcess &&
        (lower.contains('lmkd') || lower.contains('low memory')) &&
        (lower.contains('kill') || lower.contains('killing'))) {
      events.add(AcceptanceRuntimeEventType.lowMemoryKill);
    }
  }
  return Set.unmodifiable(events);
}

int? _threadtimePid(String line) {
  final match = RegExp(
    r'^\d\d-\d\d\s+\d\d:\d\d:\d\d\.\d+\s+(\d+)\s+\d+',
  ).firstMatch(line);
  return int.tryParse(match?.group(1) ?? '');
}
