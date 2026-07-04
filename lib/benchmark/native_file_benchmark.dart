import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'benchmark_result.dart';
import 'image_benchmark.dart';
import 'peak_rss_sampler.dart';

/// Passes only a file path (not bytes) to Kotlin. Kotlin reads, decodes,
/// resizes, encodes, and saves entirely on the native side with no byte copy
/// across the Flutter bridge. This represents "pure native" speed and isolates
/// the MethodChannel copy cost from the compute cost.
class NativeFileBenchmark implements ImageBenchmark {
  static const _channel = MethodChannel('rush_demo/native');

  @override
  String get name => 'Native (file path, no copy)';

  static bool get isSupported => Platform.isAndroid;

  @override
  Future<BenchmarkResult> run(Uint8List source) async {
    if (!isSupported) {
      throw UnsupportedError('Native file benchmark is Android-only.');
    }

    // Write source bytes to a temp file — NOT timed, this is just setup.
    final dir = await getTemporaryDirectory();
    final tmpFile = File(
      '${dir.path}/rush_src_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await tmpFile.writeAsBytes(source);

    final sampler = PeakRssSampler()..start();
    final totalSw = Stopwatch()..start();

    // The bridge only carries a path string (~O(1) bytes) — no image bytes copied.
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'readProcessSave',
      {'path': tmpFile.path, 'width': 800, 'height': 600, 'quality': 85},
    );

    totalSw.stop();
    final peakRss = sampler.stop();

    await tmpFile.delete();

    final decodeMs = raw!['decodeMs'] as int;
    final processMs = raw['processMs'] as int;
    final encodeMs = raw['encodeMs'] as int;
    final saveMs = raw['saveMs'] as int;
    final outputBytes = raw['outputBytes'] as int;
    final nativeComputeMs = decodeMs + processMs + encodeMs + saveMs;

    return BenchmarkResult(
      implName: name,
      totalMs: totalSw.elapsedMilliseconds,
      decodeMs: decodeMs,
      processMs: processMs,
      encodeMs: encodeMs,
      saveMs: saveMs,
      outputBytes: outputBytes,
      outputWidth: 800,
      outputHeight: 600,
      peakRssDeltaBytes: peakRss,
      nativeComputeMs: nativeComputeMs,
    );
  }
}
