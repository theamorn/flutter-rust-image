import 'dart:isolate';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:pixer/pixer.dart';

import 'benchmark_result.dart';
import 'image_benchmark.dart';
import 'peak_rss_sampler.dart';

class PixerBenchmark implements ImageBenchmark {
  @override
  String get name => 'Rust FFI (pixer)';

  @override
  Future<BenchmarkResult> run(Uint8List source) async {
    final sampler = PeakRssSampler()..start();
    final totalSw = Stopwatch()..start();

    final result = await Isolate.run<Map<String, dynamic>>(
      () => _processInIsolate(source),
    );

    final jpeg = result['jpeg'] as Uint8List;

    final saveSw = Stopwatch()..start();
    await Gal.putImageBytes(
      jpeg,
      name: 'rush_pixer_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final saveMs = saveSw.elapsedMilliseconds;

    totalSw.stop();
    final peakRss = sampler.stop();

    return BenchmarkResult(
      implName: name,
      totalMs: totalSw.elapsedMilliseconds,
      decodeMs: result['decodeMs'] as int,
      processMs: result['processMs'] as int,
      encodeMs: result['encodeMs'] as int,
      saveMs: saveMs,
      outputBytes: jpeg.length,
      outputWidth: 800,
      outputHeight: 600,
      peakRssDeltaBytes: peakRss,
    );
  }
}

Map<String, dynamic> _processInIsolate(Uint8List bytes) {
  final decodeSw = Stopwatch()..start();
  final src = Pixer.fromMemory(bytes);
  final decodeMs = decodeSw.elapsedMilliseconds;

  final processSw = Stopwatch()..start();
  // Triangle = bilinear, matching the Kotlin path's filter for a fair
  // codec-vs-codec comparison (pixer defaults to Lanczos3).
  final resized = src.resizeExact(800, 600, filter: FilterTypeEnum.Triangle);
  src.dispose();
  final processMs = processSw.elapsedMilliseconds;

  final encodeSw = Stopwatch()..start();
  final jpeg = resized.encode(PixerJpegEncoder(quality: 85));
  resized.dispose();
  final encodeMs = encodeSw.elapsedMilliseconds;

  return {
    'jpeg': jpeg,
    'decodeMs': decodeMs,
    'processMs': processMs,
    'encodeMs': encodeMs,
  };
}
