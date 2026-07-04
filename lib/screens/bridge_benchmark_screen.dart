import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../benchmark/payload_benchmark.dart';
import '../benchmark/slider_benchmark.dart';
import 'live_editor_screen.dart';

/// Two benchmarks that isolate the BRIDGE cost (not codec speed):
/// chatty calls (editor slider) and payload scaling (zero-copy).
class BridgeBenchmarkScreen extends StatefulWidget {
  final Uint8List sourceBytes;

  const BridgeBenchmarkScreen({super.key, required this.sourceBytes});

  @override
  State<BridgeBenchmarkScreen> createState() => _BridgeBenchmarkScreenState();
}

class _BridgeBenchmarkScreenState extends State<BridgeBenchmarkScreen> {
  SliderBenchmarkResult? _sliderResult;
  List<PayloadPoint>? _payloadPoints;
  bool _sliderRunning = false;
  bool _payloadRunning = false;

  Future<void> _runSlider() async {
    setState(() => _sliderRunning = true);
    try {
      final result = await SliderBenchmark().run(widget.sourceBytes);
      if (mounted) setState(() => _sliderResult = result);
    } catch (e) {
      _showError('Editor slider: $e');
    } finally {
      if (mounted) setState(() => _sliderRunning = false);
    }
  }

  Future<void> _runPayload() async {
    setState(() => _payloadRunning = true);
    try {
      final points = await PayloadBenchmark().run();
      if (mounted) setState(() => _payloadPoints = points);
    } catch (e) {
      _showError('Payload scaling: $e');
    } finally {
      if (mounted) setState(() => _payloadRunning = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bridge Benchmarks'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (kDebugMode)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              color: Colors.red.shade900,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: const Text(
                '⚠ DEBUG BUILD — numbers are meaningless. Run in release/profile mode.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 8),
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: const Icon(
                Icons.auto_awesome,
                color: Colors.purpleAccent,
              ),
              title: const Text('Live Editor'),
              subtitle: const Text(
                'Feel the difference — drag a slider, flip Channel vs FFI',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      LiveEditorScreen(sourceBytes: widget.sourceBytes),
                ),
              ),
            ),
          ),
          _SliderCard(
            result: _sliderResult,
            isRunning: _sliderRunning,
            isDisabled: _payloadRunning,
            onRun: _runSlider,
          ),
          _PayloadCard(
            points: _payloadPoints,
            isRunning: _payloadRunning,
            isDisabled: _sliderRunning,
            onRun: _runPayload,
          ),
        ],
      ),
    );
  }
}

// ─── Editor slider card ──────────────────────────────────────────────────────

class _SliderCard extends StatelessWidget {
  final SliderBenchmarkResult? result;
  final bool isRunning;
  final bool isDisabled;
  final VoidCallback onRun;

  const _SliderCard({
    required this.result,
    required this.isRunning,
    required this.isDisabled,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              icon: Icons.tune,
              iconColor: Colors.orange,
              title: 'Editor slider',
              subtitle:
                  '60 brightness ticks on an 800×600 preview — '
                  'one second of dragging',
              isRunning: isRunning,
              isDisabled: isDisabled,
              onRun: onRun,
            ),
            if (r != null) ...[
              const SizedBox(height: 12),
              _PathResult(
                label: 'MethodChannel',
                color: Colors.orange,
                totalMs: r.channelTotalMs,
                avgTickMs: r.channelAvgTickMs,
                maxTickMs: r.channelMaxTickMs,
                detail:
                    '${(r.channelBytesCopied / (1024 * 1024)).toStringAsFixed(0)}'
                    ' MB copied over the bridge',
                fraction: 1.0,
              ),
              const SizedBox(height: 10),
              _PathResult(
                label: 'Rust FFI (pixer)',
                color: Colors.green,
                totalMs: r.ffiTotalMs,
                avgTickMs: r.ffiAvgTickMs,
                maxTickMs: r.ffiMaxTickMs,
                detail: '0 bytes copied — pixels stay in native memory',
                fraction: r.channelTotalMs > 0
                    ? (r.ffiTotalMs / r.channelTotalMs).clamp(0.01, 1.0)
                    : 1.0,
              ),
              const SizedBox(height: 10),
              const Text(
                'Caveat: brightness runs via ColorMatrix (Kotlin) vs Rust — '
                'different implementations, but compute is a few ms while the '
                'bridge copies dominate the channel path.',
                style: TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PathResult extends StatelessWidget {
  final String label;
  final Color color;
  final double totalMs;
  final double avgTickMs;
  final double maxTickMs;
  final String detail;
  final double fraction;

  const _PathResult({
    required this.label,
    required this.color,
    required this.totalMs,
    required this.avgTickMs,
    required this.maxTickMs,
    required this.detail,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    final withinBudget = avgTickMs <= 16;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
            Text(
              '${_fmtMs(avgTickMs)}/tick',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: withinBudget ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              withinBudget ? '✓ within 16ms budget' : '✗ blows 16ms budget',
              style: TextStyle(
                fontSize: 10,
                color: withinBudget ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _Bar(fraction: fraction, color: color),
        const SizedBox(height: 4),
        Text(
          'total ${_fmtMs(totalMs)} · worst tick ${_fmtMs(maxTickMs)} · $detail',
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
      ],
    );
  }
}

// ─── Payload scaling card ────────────────────────────────────────────────────

class _PayloadCard extends StatelessWidget {
  final List<PayloadPoint>? points;
  final bool isRunning;
  final bool isDisabled;
  final VoidCallback onRun;

  const _PayloadCard({
    required this.points,
    required this.isRunning,
    required this.isDisabled,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final ps = points;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              icon: Icons.swap_vert,
              iconColor: Colors.lightBlueAccent,
              title: 'Payload scaling',
              subtitle:
                  'Round-trip a buffer to native and back — channel '
                  'copies twice, FFI shares one allocation (median of 3)',
              isRunning: isRunning,
              isDisabled: isDisabled,
              onRun: onRun,
            ),
            if (ps != null) ...[
              const SizedBox(height: 12),
              for (final p in ps) _PayloadRow(point: p),
              const SizedBox(height: 4),
              const Text(
                'Identical native work both paths (fill every byte). The gap '
                'is purely serialization + copies.',
                style: TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PayloadRow extends StatelessWidget {
  final PayloadPoint point;

  const _PayloadRow({required this.point});

  @override
  Widget build(BuildContext context) {
    final maxMs = point.channelMs > point.ffiMs ? point.channelMs : point.ffiMs;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${point.sizeMB.toStringAsFixed(0)} MB',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          _LabeledBar(
            label: 'channel',
            ms: point.channelMs,
            fraction: maxMs > 0
                ? (point.channelMs / maxMs).clamp(0.01, 1.0)
                : 1.0,
            color: Colors.orange,
          ),
          const SizedBox(height: 2),
          _LabeledBar(
            label: 'FFI',
            ms: point.ffiMs,
            fraction: maxMs > 0 ? (point.ffiMs / maxMs).clamp(0.01, 1.0) : 1.0,
            color: Colors.green,
          ),
        ],
      ),
    );
  }
}

// ─── Shared pieces ───────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isRunning;
  final bool isDisabled;
  final VoidCallback onRun;

  const _CardHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isRunning,
    required this.isDisabled,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
        ),
        if (isRunning)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          TextButton(
            onPressed: isDisabled ? null : onRun,
            child: const Text('Run'),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double fraction;
  final Color color;

  const _Bar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 14,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction,
          child: Container(color: color),
        ),
      ),
    );
  }
}

class _LabeledBar extends StatelessWidget {
  final String label;
  final double ms;
  final double fraction;
  final Color color;

  const _LabeledBar({
    required this.label,
    required this.ms,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ),
        Expanded(
          child: _Bar(fraction: fraction, color: color),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(
            _fmtMs(ms),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }
}

String _fmtMs(double ms) {
  if (ms >= 100) return '${ms.toStringAsFixed(0)}ms';
  if (ms >= 1) return '${ms.toStringAsFixed(1)}ms';
  return '${ms.toStringAsFixed(2)}ms';
}
