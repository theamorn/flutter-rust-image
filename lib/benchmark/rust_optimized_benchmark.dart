import 'dart:typed_data';

import 'package:gal/gal.dart';

import '../src/rust/api/image_pipeline.dart';
import 'benchmark_result.dart';
import 'image_benchmark.dart';
import 'peak_rss_sampler.dart';

class RustOptimizedBenchmark implements ImageBenchmark {
  @override
  String get name => 'Rust FFI (optimized)';

  @override
  Future<BenchmarkResult> run(Uint8List source) async {
    final sampler = PeakRssSampler()..start();
    final totalSw = Stopwatch()..start();

    // Single FFI call; frb runs the Rust work off the UI isolate, so no
    // Isolate.run wrapper is needed (unlike pixer's three sync calls).
    final result = await processImage(jpeg: source, w: 800, h: 600, quality: 85);

    final saveSw = Stopwatch()..start();
    await Gal.putImageBytes(
      result.jpeg,
      name: 'rush_rustopt_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final saveMs = saveSw.elapsedMilliseconds;

    totalSw.stop();
    final peakRss = sampler.stop();

    return BenchmarkResult(
      implName: name,
      totalMs: totalSw.elapsedMilliseconds,
      decodeMs: result.decodeMs,
      processMs: result.processMs,
      encodeMs: result.encodeMs,
      saveMs: saveMs,
      outputBytes: result.jpeg.length,
      outputWidth: 800,
      outputHeight: 600,
      peakRssDeltaBytes: peakRss,
    );
  }
}
