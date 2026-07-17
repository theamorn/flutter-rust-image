import 'dart:io';

import 'package:flutter/services.dart';

import 'benchmark_result.dart';
import 'image_benchmark.dart';
import 'peak_rss_sampler.dart';

class MethodChannelBenchmark implements ImageBenchmark {
  static const _channel = MethodChannel('rush_demo/native');

  @override
  String get name =>
      Platform.isIOS ? 'MethodChannel (Swift)' : 'MethodChannel (Kotlin)';

  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  @override
  Future<BenchmarkResult> run(Uint8List source) async {
    if (!isSupported) {
      throw UnsupportedError('MethodChannel benchmark is mobile-only.');
    }

    final sampler = PeakRssSampler()..start();
    final totalSw = Stopwatch()..start();

    // The full round-trip: Dart serializes bytes → channel copies → native
    // thread (Kotlin/Swift) → native compute + gallery save → result
    // deserialized back to Dart. This copy cost is the central thesis of the talk.
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'resizeCompressSave',
      {'bytes': source, 'width': 800, 'height': 600, 'quality': 85},
    );

    totalSw.stop();
    final peakRss = sampler.stop();

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
