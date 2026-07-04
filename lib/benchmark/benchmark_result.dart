class BenchmarkResult {
  final String implName;
  final int totalMs;
  final int decodeMs;
  final int processMs;
  final int encodeMs;
  final int saveMs;
  final int outputBytes;
  final int outputWidth;
  final int outputHeight;
  final int peakRssDeltaBytes;
  // MethodChannel only: sum of native-side phase timings (Kotlin clock)
  final int? nativeComputeMs;
  // DartBlockingBenchmark only: frames the UI missed while the main isolate was frozen
  final int? droppedFrames;

  const BenchmarkResult({
    required this.implName,
    required this.totalMs,
    required this.decodeMs,
    required this.processMs,
    required this.encodeMs,
    required this.saveMs,
    required this.outputBytes,
    required this.outputWidth,
    required this.outputHeight,
    required this.peakRssDeltaBytes,
    this.nativeComputeMs,
    this.droppedFrames,
  });

  // Bridge overhead = total Dart-measured round-trip minus native compute (the copy cost)
  int? get boundaryMs =>
      nativeComputeMs != null ? totalMs - nativeComputeMs! : null;

  static String get csvHeader =>
      'impl,totalMs,decodeMs,processMs,encodeMs,saveMs,'
      'nativeComputeMs,boundaryMs,outputBytes,outputWidth,outputHeight,'
      'peakRssDeltaBytes,droppedFrames';

  String toCsvRow() =>
      '$implName,$totalMs,$decodeMs,$processMs,$encodeMs,$saveMs,'
      '${nativeComputeMs ?? ""},'
      '${boundaryMs ?? ""},'
      '$outputBytes,$outputWidth,$outputHeight,'
      '$peakRssDeltaBytes,'
      '${droppedFrames ?? ""}';
}
