/// Editor-slider benchmark: simulates one second of dragging a brightness
/// slider (60 ticks) over an 800×600 preview.
///
/// MethodChannel path: Dart owns the pixels (raw RGBA), so every tick ships
/// ~1.9 MB to Kotlin and ~1.9 MB back. FFI path: the preview lives in native
/// memory as a pixer handle; each tick passes only an integer.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:pixer/pixer.dart';

class SliderBenchmarkResult {
  final int ticks;
  final int channelTotalUs;
  final int ffiTotalUs;
  final int channelMaxTickUs;
  final int ffiMaxTickUs;
  final int rgbaBytesPerFrame;

  const SliderBenchmarkResult({
    required this.ticks,
    required this.channelTotalUs,
    required this.ffiTotalUs,
    required this.channelMaxTickUs,
    required this.ffiMaxTickUs,
    required this.rgbaBytesPerFrame,
  });

  double get channelTotalMs => channelTotalUs / 1000;
  double get ffiTotalMs => ffiTotalUs / 1000;
  double get channelAvgTickMs => channelTotalUs / ticks / 1000;
  double get ffiAvgTickMs => ffiTotalUs / ticks / 1000;
  double get channelMaxTickMs => channelMaxTickUs / 1000;
  double get ffiMaxTickMs => ffiMaxTickUs / 1000;

  /// RGBA out + RGBA back, every tick. The FFI path copies zero bytes.
  int get channelBytesCopied => 2 * rgbaBytesPerFrame * ticks;
}

class SliderBenchmark {
  static const _channel = MethodChannel('rush_demo/native');
  static const int ticks = 60;
  static const int _warmupTicks = 3;
  static const int previewWidth = 800;
  static const int previewHeight = 600;

  static bool get isSupported => Platform.isAndroid;

  /// Brightness for tick [i]: linear sweep −30 → +30, like a real drag.
  static int valueForTick(int i, int totalTicks) =>
      -30 + (60 * i) ~/ (totalTicks - 1);

  Future<SliderBenchmarkResult> run(Uint8List sourceJpeg) async {
    if (!isSupported) {
      throw UnsupportedError('Slider benchmark is Android-only.');
    }

    // Setup (untimed): channel path — Dart-owned RGBA preview.
    final rgba = await _decodeToRgba(sourceJpeg);

    // Setup (untimed): FFI path — preview stays in native memory.
    final source = Pixer.fromMemory(sourceJpeg);
    final Pixer preview;
    try {
      preview = source.resizeExact(previewWidth, previewHeight);
    } finally {
      source.dispose();
    }

    try {
      for (var i = 0; i < _warmupTicks; i++) {
        await _channelTick(rgba, 0);
        preview.brightness(0).dispose();
      }

      var channelMaxUs = 0;
      final channelSw = Stopwatch()..start();
      for (var i = 0; i < ticks; i++) {
        final tickSw = Stopwatch()..start();
        await _channelTick(rgba, valueForTick(i, ticks));
        final us = tickSw.elapsedMicroseconds;
        if (us > channelMaxUs) channelMaxUs = us;
      }
      final channelTotalUs = channelSw.elapsedMicroseconds;

      var ffiMaxUs = 0;
      final ffiSw = Stopwatch()..start();
      for (var i = 0; i < ticks; i++) {
        final tickSw = Stopwatch()..start();
        preview.brightness(valueForTick(i, ticks)).dispose();
        final us = tickSw.elapsedMicroseconds;
        if (us > ffiMaxUs) ffiMaxUs = us;
      }
      final ffiTotalUs = ffiSw.elapsedMicroseconds;

      return SliderBenchmarkResult(
        ticks: ticks,
        channelTotalUs: channelTotalUs,
        ffiTotalUs: ffiTotalUs,
        channelMaxTickUs: channelMaxUs,
        ffiMaxTickUs: ffiMaxUs,
        rgbaBytesPerFrame: rgba.length,
      );
    } finally {
      preview.dispose();
    }
  }

  Future<Uint8List> _decodeToRgba(Uint8List jpeg) async {
    final codec = await ui.instantiateImageCodec(
      jpeg,
      targetWidth: previewWidth,
      targetHeight: previewHeight,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    codec.dispose();
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<Uint8List> _channelTick(Uint8List rgba, int value) async {
    final out = await _channel.invokeMethod<Uint8List>('adjustBrightness', {
      'rgba': rgba,
      'width': previewWidth,
      'height': previewHeight,
      'value': value,
    });
    return out!;
  }
}
