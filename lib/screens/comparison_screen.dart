import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../benchmark/benchmark_result.dart';

class ComparisonScreen extends StatelessWidget {
  final List<BenchmarkResult> results;
  final Uint8List sourceBytes;
  final int? sourceWidth;
  final int? sourceHeight;
  final String deviceLabel;

  const ComparisonScreen({
    super.key,
    required this.results,
    required this.sourceBytes,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.deviceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...results]..sort((a, b) => a.totalMs.compareTo(b.totalMs));
    final fastest = sorted.first;
    final slowest = sorted.last;
    final maxMs = slowest.totalMs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Comparison'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sourceRow(context),
          const SizedBox(height: 24),
          ...sorted.map(
            (r) => _BarRow(result: r, maxMs: maxMs, fastest: fastest),
          ),
          const SizedBox(height: 24),
          _insightBox(context, sorted),
        ],
      ),
    );
  }

  Widget _sourceRow(BuildContext context) {
    final sizeKb = (sourceBytes.length / 1024).toStringAsFixed(0);
    final dims = (sourceWidth != null && sourceHeight != null)
        ? '$sourceWidth×$sourceHeight'
        : '?';
    return Row(
      children: [
        const Icon(Icons.photo, size: 16, color: Colors.white54),
        const SizedBox(width: 6),
        Text(
          'Source: $dims · ${sizeKb}KB  ·  Target: 800×600 JPEG q85',
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
        if (deviceLabel.isNotEmpty) ...[
          const Text('  ·  ', style: TextStyle(color: Colors.white24)),
          Text(
            deviceLabel,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ],
    );
  }

  Widget _insightBox(BuildContext context, List<BenchmarkResult> sorted) {
    final fastest = sorted.first;
    final slowest = sorted.last;
    final ratio = (slowest.totalMs / fastest.totalMs.clamp(1, 999999))
        .toStringAsFixed(1);

    final mcResult = sorted.cast<BenchmarkResult?>().firstWhere(
      (r) => r?.implName.contains('MethodChannel') == true,
      orElse: () => null,
    );
    final rustResult = sorted.cast<BenchmarkResult?>().firstWhere(
      (r) => r?.implName.contains('Rust') == true,
      orElse: () => null,
    );

    final lines = <String>[
      '${slowest.implName} is $ratio× slower than ${fastest.implName}.',
    ];

    if (mcResult != null && rustResult != null) {
      final mcRatio = (mcResult.totalMs / rustResult.totalMs.clamp(1, 999999))
          .toStringAsFixed(1);
      lines.add('MethodChannel is $mcRatio× slower than Rust FFI.');
    }

    if (mcResult?.boundaryMs != null) {
      final pct = ((mcResult!.boundaryMs! / mcResult.totalMs) * 100)
          .toStringAsFixed(0);
      lines.add(
        'Bridge copy overhead: ${mcResult.boundaryMs}ms ($pct% of MethodChannel total).',
      );
    }

    lines.add('The copy is the cost — not the compute.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Key insight',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          ...lines.map(
            (l) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(l, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Single bar row ───────────────────────────────────────────────────────────

class _BarRow extends StatelessWidget {
  final BenchmarkResult result;
  final int maxMs;
  final BenchmarkResult fastest;

  const _BarRow({
    required this.result,
    required this.maxMs,
    required this.fastest,
  });

  @override
  Widget build(BuildContext context) {
    final isFastest = result.implName == fastest.implName;
    final ratio = result.totalMs / fastest.totalMs.clamp(1, 999999);
    final color = _colorFor(result.implName);
    final barFlex = result.totalMs.clamp(1, maxMs);
    final spacerFlex = (maxMs - barFlex).clamp(0, maxMs);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(result.implName), color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  result.implName,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${result.totalMs}ms',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isFastest ? Colors.greenAccent : Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: barFlex,
                child: Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              if (spacerFlex > 0)
                Expanded(flex: spacerFlex, child: const SizedBox()),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isFastest
                ? '🏆 fastest'
                : '${ratio.toStringAsFixed(1)}× slower than ${fastest.implName}',
            style: TextStyle(
              fontSize: 11,
              color: isFastest ? Colors.greenAccent : Colors.white54,
            ),
          ),
          if (result.droppedFrames != null)
            Text(
              '~${result.droppedFrames} frames dropped during freeze',
              style: const TextStyle(fontSize: 11, color: Colors.red),
            ),
        ],
      ),
    );
  }

  Color _colorFor(String name) {
    if (name.contains('blocking')) return Colors.red;
    if (name.contains('Pure Dart')) return Colors.blue;
    if (name.contains('MethodChannel')) return Colors.orange;
    if (name.contains('Rust')) return Colors.green;
    if (name.contains('file path')) return Colors.teal;
    return Colors.grey;
  }

  IconData _iconFor(String name) {
    if (name.contains('blocking')) return Icons.warning_amber;
    if (name.contains('Pure Dart')) return Icons.code;
    if (name.contains('MethodChannel')) return Icons.swap_horiz;
    if (name.contains('Rust')) return Icons.speed;
    if (name.contains('file path')) return Icons.smartphone;
    return Icons.help_outline;
  }
}
