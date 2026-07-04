import 'dart:isolate';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;

import 'benchmark_result.dart';
import 'image_benchmark.dart';
import 'peak_rss_sampler.dart';

class DartBenchmark implements ImageBenchmark {
  @override
  String get name => 'Pure Dart';

  @override
  Future<BenchmarkResult> run(Uint8List source) async {
    final sampler = PeakRssSampler()..start();
    final totalSw = Stopwatch()..start();

    final result = await Isolate.run<Map<String, dynamic>>(
      () => _processInIsolate(source),
    );

    final encodeMs = result['encodeMs'] as int;
    final jpeg = result['jpeg'] as Uint8List;

    final saveSw = Stopwatch()..start();
    await Gal.putImageBytes(
      jpeg,
      name: 'rush_dart_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final saveMs = saveSw.elapsedMilliseconds;

    totalSw.stop();
    final peakRss = sampler.stop();

    return BenchmarkResult(
      implName: name,
      totalMs: totalSw.elapsedMilliseconds,
      decodeMs: result['decodeMs'] as int,
      processMs: result['processMs'] as int,
      encodeMs: encodeMs,
      saveMs: saveMs,
      outputBytes: jpeg.length,
      outputWidth: 800,
      outputHeight: 600,
      peakRssDeltaBytes: peakRss,
    );
  }
}

// Top-level so Isolate.run can send it across the isolate boundary.
Map<String, dynamic> _processInIsolate(Uint8List bytes) {
  final decodeSw = Stopwatch()..start();
  final decoded = img.decodeImage(bytes)!;
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

  return {
    'jpeg': jpeg,
    'decodeMs': decodeMs,
    'processMs': processMs,
    'encodeMs': encodeMs,
  };
}
