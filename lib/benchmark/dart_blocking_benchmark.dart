import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;

import 'benchmark_result.dart';
import 'image_benchmark.dart';
import 'peak_rss_sampler.dart';

/// Runs image processing on the main isolate — no Isolate.run.
///
/// This is what most apps do accidentally. The Dart thread blocks for the
/// entire decode→resize→encode pipeline, causing visible jank/dropped frames.
/// Compare its totalMs to DartBenchmark to see the Isolate.run spawn overhead,
/// and observe the UI freeze on stage using the performance overlay.
class DartBlockingBenchmark implements ImageBenchmark {
  static const _targetFps = 60;

  @override
  String get name => 'Pure Dart (blocking, no isolate)';

  @override
  Future<BenchmarkResult> run(Uint8List source) async {
    final sampler = PeakRssSampler()..start();
    final totalSw = Stopwatch()..start();

    // All of this runs synchronously on the main Dart isolate.
    // The UI is completely unresponsive until encode() returns.
    final decodeSw = Stopwatch()..start();
    final decoded = img.decodeImage(source)!;
    final decodeMs = decodeSw.elapsedMilliseconds;

    final processSw = Stopwatch()..start();
    final resized = img.copyResize(
      decoded,
      width: 800,
      height: 600,
      maintainAspect: false,
      interpolation: img.Interpolation.cubic,
    );
    final processMs = processSw.elapsedMilliseconds;

    final encodeSw = Stopwatch()..start();
    final jpeg = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
    final encodeMs = encodeSw.elapsedMilliseconds;

    // save is async — the main isolate is no longer blocked here.
    final saveSw = Stopwatch()..start();
    await Gal.putImageBytes(
      jpeg,
      name: 'rush_dart_blocking_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final saveMs = saveSw.elapsedMilliseconds;

    totalSw.stop();
    final peakRss = sampler.stop();

    // Estimate frames the display missed while the main isolate was frozen.
    // save() is async so it's excluded — only decode+process+encode block rendering.
    final frozenMs = decodeMs + processMs + encodeMs;
    final droppedFrames = (frozenMs / (1000.0 / _targetFps)).round();

    return BenchmarkResult(
      implName: name,
      totalMs: totalSw.elapsedMilliseconds,
      decodeMs: decodeMs,
      processMs: processMs,
      encodeMs: encodeMs,
      saveMs: saveMs,
      outputBytes: jpeg.length,
      outputWidth: 800,
      outputHeight: 600,
      peakRssDeltaBytes: peakRss,
      droppedFrames: droppedFrames,
    );
  }
}
