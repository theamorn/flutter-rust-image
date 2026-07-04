import 'dart:io';
import 'dart:isolate';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../benchmark/benchmark_result.dart';
import '../benchmark/dart_benchmark.dart';
import '../benchmark/dart_blocking_benchmark.dart';
import '../benchmark/image_benchmark.dart';
import '../benchmark/method_channel_benchmark.dart';
import '../benchmark/native_file_benchmark.dart';
import '../benchmark/pixer_benchmark.dart';
import '../benchmark/rust_optimized_benchmark.dart';
import 'comparison_screen.dart';
import 'bridge_benchmark_screen.dart';

/// Stage-reveal tiers: each tap of the rocket unlocks the next act of the
/// double twist (off = Dart only → turbo = native contenders → super turbo =
/// optimized Rust).
enum _TurboMode { off, turbo, superTurbo }

class BenchmarkScreen extends StatefulWidget {
  final Uint8List sourceBytes;

  const BenchmarkScreen({super.key, required this.sourceBytes});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  final _benchmarks = [
    DartBlockingBenchmark(),
    DartBenchmark(),
    MethodChannelBenchmark(),
    PixerBenchmark(),
    RustOptimizedBenchmark(),
    NativeFileBenchmark(),
  ];

  final Map<String, BenchmarkResult?> _results = {};
  final Map<String, bool> _running = {};

  _TurboMode _mode = _TurboMode.off;

  bool _isVisible(ImageBenchmark bm) => switch (bm) {
    DartBlockingBenchmark() || DartBenchmark() => true,
    RustOptimizedBenchmark() => _mode == _TurboMode.superTurbo,
    _ => _mode != _TurboMode.off,
  };

  void _cycleTurbo() {
    setState(() {
      _mode = switch (_mode) {
        _TurboMode.off => _TurboMode.turbo,
        _TurboMode.turbo => _TurboMode.superTurbo,
        _TurboMode.superTurbo => _TurboMode.off,
      };
    });
    final msg = switch (_mode) {
      _TurboMode.off => null,
      _TurboMode.turbo => '🚀 TURBO MODE — native contenders unlocked',
      _TurboMode.superTurbo => '⚡ SUPER TURBO — optimized Rust unlocked',
    };
    if (msg != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
        );
    }
  }

  int? _sourceWidth;
  int? _sourceHeight;
  String _deviceLabel = '';

  @override
  void initState() {
    super.initState();
    _loadSourceInfo();
    _loadDeviceInfo();
  }

  Future<void> _loadSourceInfo() async {
    final dims = await Isolate.run<(int, int)>(() {
      final decoded = img.decodeImage(widget.sourceBytes);
      return (decoded?.width ?? 0, decoded?.height ?? 0);
    });
    if (mounted)
      setState(() {
        _sourceWidth = dims.$1;
        _sourceHeight = dims.$2;
      });
  }

  Future<void> _loadDeviceInfo() async {
    final plugin = DeviceInfoPlugin();
    String label;
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      label = '${info.model} · Android ${info.version.sdkInt}';
    } else if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      label = '${info.model} · iOS ${info.systemVersion}';
    } else {
      label = Platform.operatingSystem;
    }
    if (mounted) setState(() => _deviceLabel = label);
  }

  Future<void> _run(ImageBenchmark bm) async {
    setState(() => _running[bm.name] = true);
    try {
      final result = await bm.run(widget.sourceBytes);
      if (mounted) setState(() => _results[bm.name] = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${bm.name}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _running[bm.name] = false);
    }
  }

  Future<void> _runAll() async {
    for (final bm in _benchmarks) {
      if (!_isVisible(bm)) continue;
      // Blocking benchmark is a deliberate stage demo — exclude from Run All
      // to avoid freezing the UI during automated comparison runs.
      if (bm is DartBlockingBenchmark) continue;
      if (bm is MethodChannelBenchmark && !MethodChannelBenchmark.isSupported)
        continue;
      if (bm is NativeFileBenchmark && !NativeFileBenchmark.isSupported)
        continue;
      await _run(bm);
    }
  }

  void _openComparison() {
    final completed = _results.values.whereType<BenchmarkResult>().toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComparisonScreen(
          results: completed,
          sourceBytes: widget.sourceBytes,
          sourceWidth: _sourceWidth,
          sourceHeight: _sourceHeight,
          deviceLabel: _deviceLabel,
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    final rows = _results.values.whereType<BenchmarkResult>().toList();
    if (rows.isEmpty) return;

    final sourceKb = (widget.sourceBytes.length / 1024).toStringAsFixed(0);
    final sourceDims = (_sourceWidth != null && _sourceHeight != null)
        ? '${_sourceWidth}x$_sourceHeight'
        : 'unknown';

    final buf = StringBuffer();
    buf.writeln('# Rush Flutter Benchmark Export');
    buf.writeln('# Device: $_deviceLabel');
    buf.writeln('# Source: $sourceDims · ${sourceKb}KB');
    buf.writeln('# Target: 800x600 JPEG q85');
    buf.writeln(
      '# Build: ${kDebugMode ? "DEBUG (invalid)" : "profile/release"}',
    );
    buf.writeln('#');
    buf.writeln(BenchmarkResult.csvHeader);
    for (final r in rows) {
      buf.writeln(r.toCsvRow());
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/rush_benchmark.csv');
    await file.writeAsString(buf.toString());

    await Share.shareXFiles([
      XFile(file.path, mimeType: 'text/csv'),
    ], subject: 'Rush Flutter Benchmark Results');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Benchmark'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.compare_arrows),
            tooltip: 'Bridge benchmarks',
            onPressed: Platform.isAndroid
                ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BridgeBenchmarkScreen(
                        sourceBytes: widget.sourceBytes,
                      ),
                    ),
                  )
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Compare all',
            onPressed: _results.values.whereType<BenchmarkResult>().length >= 2
                ? _openComparison
                : null,
          ),
          GestureDetector(
            // Long-press keeps CSV export reachable for the fallback slide.
            onLongPress: _results.values.any((r) => r != null)
                ? _exportCsv
                : null,
            child: IconButton(
              icon: Icon(
                Icons.rocket_launch,
                color: switch (_mode) {
                  _TurboMode.off => Colors.grey,
                  _TurboMode.turbo => Colors.amber,
                  _TurboMode.superTurbo => Colors.deepOrange,
                },
              ),
              tooltip: switch (_mode) {
                _TurboMode.off => 'Turbo mode',
                _TurboMode.turbo => 'Super turbo',
                _TurboMode.superTurbo => 'Back to slow mode',
              },
              onPressed: _cycleTurbo,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (kDebugMode)
            Container(
              width: double.infinity,
              color: Colors.red.shade900,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: const Text(
                '⚠ DEBUG BUILD — numbers are meaningless. Run in release/profile mode.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          _SourceInfoBar(
            bytes: widget.sourceBytes,
            width: _sourceWidth,
            height: _sourceHeight,
            deviceLabel: _deviceLabel,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _running.values.any((v) => v) ? null : _runAll,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run All'),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: _benchmarks.length,
              itemBuilder: (_, i) {
                final bm = _benchmarks[i];
                final isAndroidOnly =
                    (bm is MethodChannelBenchmark &&
                        !MethodChannelBenchmark.isSupported) ||
                    (bm is NativeFileBenchmark &&
                        !NativeFileBenchmark.isSupported);
                final visible = _isVisible(bm);
                return AnimatedSize(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: !visible
                      ? const SizedBox.shrink()
                      : TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 500),
                          builder: (_, v, child) =>
                              Opacity(opacity: v, child: child),
                          child: _BenchmarkCard(
                            benchmark: bm,
                            result: _results[bm.name],
                            isRunning: _running[bm.name] ?? false,
                            isDisabled: isAndroidOnly,
                            onRun: () => _run(bm),
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Source info ─────────────────────────────────────────────────────────────

class _SourceInfoBar extends StatelessWidget {
  final Uint8List bytes;
  final int? width;
  final int? height;
  final String deviceLabel;

  const _SourceInfoBar({
    required this.bytes,
    required this.width,
    required this.height,
    required this.deviceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final sizeKb = (bytes.length / 1024).toStringAsFixed(0);
    final dims = (width != null && height != null) ? '$width×$height' : '…';
    final mp = (width != null && height != null)
        ? ((width! * height!) / 1_000_000).toStringAsFixed(1)
        : '?';

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Source image',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text('$dims · $mp MP · ${sizeKb}KB'),
                if (deviceLabel.isNotEmpty)
                  Text(
                    deviceLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white54),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Benchmark card ──────────────────────────────────────────────────────────

class _BenchmarkCard extends StatelessWidget {
  final ImageBenchmark benchmark;
  final BenchmarkResult? result;
  final bool isRunning;
  final bool isDisabled;
  final VoidCallback onRun;

  const _BenchmarkCard({
    required this.benchmark,
    required this.result,
    required this.isRunning,
    required this.isDisabled,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _implIcon(benchmark),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        benchmark.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (benchmark is DartBlockingBenchmark)
                        const Text(
                          '⚠ Freezes UI — run with performance overlay on stage',
                          style: TextStyle(fontSize: 10, color: Colors.red),
                        ),
                    ],
                  ),
                ),
                if (isDisabled)
                  const Chip(
                    label: Text('Android only', style: TextStyle(fontSize: 10)),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )
                else if (isRunning)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  TextButton(onPressed: onRun, child: const Text('Run')),
              ],
            ),
            if (result != null) ...[
              const SizedBox(height: 12),
              _ResultDetail(result: result!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _implIcon(ImageBenchmark bm) {
    final (icon, color) = switch (bm) {
      DartBlockingBenchmark() => (Icons.warning_amber, Colors.red),
      DartBenchmark() => (Icons.code, Colors.blue),
      MethodChannelBenchmark() => (Icons.swap_horiz, Colors.orange),
      PixerBenchmark() => (Icons.speed, Colors.green),
      RustOptimizedBenchmark() => (Icons.rocket_launch, Colors.deepOrange),
      NativeFileBenchmark() => (Icons.smartphone, Colors.teal),
      _ => (Icons.help_outline, Colors.grey),
    };
    return Icon(icon, color: color);
  }
}

// ─── Result detail ────────────────────────────────────────────────────────────

class _ResultDetail extends StatelessWidget {
  final BenchmarkResult result;

  const _ResultDetail({required this.result});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final total = result.totalMs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Frame-drop callout (blocking Dart only) — shown first, it's the headline
        if (result.droppedFrames != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade600, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('💀', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      '~${result.droppedFrames} frames dropped',
                      style: textTheme.titleSmall?.copyWith(
                        color: Colors.red.shade200,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'UI frozen for ${result.decodeMs + result.processMs + result.encodeMs}ms'
                  ' — ${result.droppedFrames! > 1 ? "every one of those frames" : "that frame"}'
                  ' was a blank screen at 60fps',
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.red.shade300,
                  ),
                ),
              ],
            ),
          ),

        // Total time (big number)
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${total}ms',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text('total', style: textTheme.bodySmall),
          ],
        ),

        const SizedBox(height: 8),

        // Bridge overhead callout (MethodChannel only)
        if (result.boundaryMs != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade700, width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.red, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Bridge copy overhead: ${result.boundaryMs}ms'
                  '  (${((result.boundaryMs! / total) * 100).toStringAsFixed(0)}% of total)',
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.red.shade200,
                  ),
                ),
              ],
            ),
          ),

        // Phase bar
        _PhaseBar(result: result),

        const SizedBox(height: 8),

        // Phase legend
        _PhaseLegend(result: result),

        const SizedBox(height: 8),

        // Output + memory row
        Row(
          children: [
            _Chip(
              label: 'Output',
              value:
                  '${result.outputWidth}×${result.outputHeight} '
                  '· ${(result.outputBytes / 1024).toStringAsFixed(0)}KB',
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'Peak RSS +',
              value: _formatBytes(result.peakRssDeltaBytes),
            ),
          ],
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 0) return '0B';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

// ─── Phase bar ────────────────────────────────────────────────────────────────

const _phaseColors = {
  'decode': Color(0xFF2196F3),
  'process': Color(0xFFFF9800),
  'encode': Color(0xFF4CAF50),
  'save': Color(0xFF9C27B0),
};

class _PhaseBar extends StatelessWidget {
  final BenchmarkResult result;

  const _PhaseBar({required this.result});

  @override
  Widget build(BuildContext context) {
    final phases = [
      ('decode', result.decodeMs),
      ('process', result.processMs),
      ('encode', result.encodeMs),
      ('save', result.saveMs),
    ];
    final totalPhase = phases.fold(0, (s, p) => s + p.$2);
    if (totalPhase == 0) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 20,
        child: Row(
          children: phases.map((phase) {
            final flex = phase.$2.clamp(1, 999999);
            return Expanded(
              flex: flex,
              child: Container(color: _phaseColors[phase.$1]),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _PhaseLegend extends StatelessWidget {
  final BenchmarkResult result;

  const _PhaseLegend({required this.result});

  @override
  Widget build(BuildContext context) {
    final phases = [
      ('decode', result.decodeMs),
      ('process', result.processMs),
      ('encode', result.encodeMs),
      ('save', result.saveMs),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: phases.map((p) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _phaseColors[p.$1],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${p.$1} ${p.$2}ms',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;

  const _Chip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(6),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: Colors.white54),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
