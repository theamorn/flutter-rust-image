/// Payload-scaling benchmark: round-trips buffers of increasing size through
/// MethodChannel (two copies) vs FFI shared memory (zero copies), with
/// identical native work (fill every byte with 0x42) on both paths.
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

class PayloadPoint {
  final int sizeBytes;
  final int channelUs;
  final int ffiUs;

  const PayloadPoint({
    required this.sizeBytes,
    required this.channelUs,
    required this.ffiUs,
  });

  double get channelMs => channelUs / 1000;
  double get ffiMs => ffiUs / 1000;
  double get sizeMB => sizeBytes / (1024 * 1024);
}

/// Median of an odd-length sample list. Does not mutate [samples].
int medianUs(List<int> samples) {
  final sorted = [...samples]..sort();
  return sorted[sorted.length ~/ 2];
}

typedef _MemsetNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Int32,
      ffi.IntPtr,
    );
typedef _MemsetDart =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int, int);

class PayloadBenchmark {
  static const _channel = MethodChannel('rush_demo/native');
  static const sizesMB = [1, 5, 20, 50];
  static const int _timedRuns = 3;
  static const int _fillByte = 0x42;

  static bool get isSupported => Platform.isAndroid;

  Future<List<PayloadPoint>> run() async {
    if (!isSupported) {
      throw UnsupportedError('Payload benchmark is Android-only.');
    }

    // libc ships with the process on Android — no custom native build.
    final memset = ffi.DynamicLibrary.process()
        .lookupFunction<_MemsetNative, _MemsetDart>('memset');

    final points = <PayloadPoint>[];
    for (final mb in sizesMB) {
      final size = mb * 1024 * 1024;

      // ── MethodChannel: buffer lives in the Dart heap; every round trip
      //    copies it into the channel and copies the result back out.
      final dartBuffer = Uint8List(size);
      Future<int> channelRoundTripUs() async {
        final sw = Stopwatch()..start();
        final out = await _channel.invokeMethod<Uint8List>(
          'fillBuffer',
          dartBuffer,
        );
        final us = sw.elapsedMicroseconds;
        if (out![0] != _fillByte || out[size - 1] != _fillByte) {
          throw StateError('fillBuffer returned an unfilled buffer');
        }
        return us;
      }

      await channelRoundTripUs(); // warm-up
      final channelSamples = <int>[
        for (var i = 0; i < _timedRuns; i++) await channelRoundTripUs(),
      ];

      // ── FFI: one buffer in native memory; Dart's view and memset touch the
      //    same bytes. Nothing crosses the boundary.
      final ptr = malloc.allocate<ffi.Uint8>(size);
      try {
        final view = ptr.asTypedList(size);
        int ffiRoundTripUs() {
          view[0] = 0;
          view[size - 1] = 0;
          final sw = Stopwatch()..start();
          memset(ptr.cast(), _fillByte, size);
          final us = sw.elapsedMicroseconds;
          if (view[0] != _fillByte || view[size - 1] != _fillByte) {
            throw StateError('memset did not fill the shared buffer');
          }
          return us;
        }

        ffiRoundTripUs(); // warm-up
        final ffiSamples = <int>[
          for (var i = 0; i < _timedRuns; i++) ffiRoundTripUs(),
        ];

        points.add(
          PayloadPoint(
            sizeBytes: size,
            channelUs: medianUs(channelSamples),
            ffiUs: medianUs(ffiSamples),
          ),
        );
      } finally {
        malloc.free(ptr);
      }
    }
    return points;
  }
}
