import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../benchmark/live_effects_ffi.dart';

enum EditorTransport { channel, ffi }

enum EditorEffect {
  brightness('Brightness'),
  pixelate('Pixelate'),
  glitch('Glitch');

  final String label;
  const EditorEffect(this.label);
}

enum EditorResolution {
  sd('SD', 800, 600),
  hd('HD', 1600, 1200),
  full('Full', 3200, 2400);

  final String label;
  final int width;
  final int height;
  const EditorResolution(this.label, this.width, this.height);

  double get frameMB => width * height * 4 / (1024 * 1024);
}

/// Live demo of transport cost: same hand-written pixel effects, applied per
/// slider tick via MethodChannel (frame crosses the bridge both ways) or FFI
/// (shared native buffers, zero copies). Both end in the identical
/// decodeImageFromPixels display step.
class LiveEditorScreen extends StatefulWidget {
  final Uint8List sourceBytes;

  const LiveEditorScreen({super.key, required this.sourceBytes});

  @override
  State<LiveEditorScreen> createState() => _LiveEditorScreenState();
}

class _LiveEditorScreenState extends State<LiveEditorScreen> {
  static const _channel = MethodChannel('rush_demo/native');

  final _ffi = LiveEffectsFfi();
  EditorTransport _transport = EditorTransport.ffi;
  EditorEffect _effect = EditorEffect.pixelate;
  EditorResolution _resolution = EditorResolution.sd;
  double _intensity = 40;
  bool _pulse = false;
  Timer? _pulseTimer;

  Uint8List? _sourceRgba; // Dart-heap copy for the channel path
  ui.Image? _image;
  bool _loadingSource = true;
  Future<void>? _activeDrain;
  bool _disposed = false;
  int? _pendingValue;

  int _lastApplyUs = 0;
  final List<int> _recentUs = [];
  int _bridgeBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadSource();
  }

  @override
  void dispose() {
    _disposed = true;
    _pulseTimer?.cancel();
    _image?.dispose();
    if (_activeDrain == null) _ffi.dispose();
    super.dispose();
  }

  Future<void> _loadSource() async {
    setState(() => _loadingSource = true);
    _pendingValue = null;
    await _activeDrain; // let any in-flight apply finish before realloc
    final res = _resolution;
    final codec = await ui.instantiateImageCodec(
      widget.sourceBytes,
      targetWidth: res.width,
      targetHeight: res.height,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    frame.image.dispose();
    codec.dispose();
    if (!mounted) return;
    final rgba = data!.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    _sourceRgba = rgba;
    _ffi.setSource(rgba);
    setState(() => _loadingSource = false);
    _enqueue(_intensity.round());
  }

  /// Newest value wins; one apply in flight at a time. In channel mode the
  /// preview visibly trails the slider — that lag IS the demo.
  void _enqueue(int value) {
    _pendingValue = value;
    if (_loadingSource) return;
    _activeDrain ??= _drain().whenComplete(() {
      _activeDrain = null;
      if (_disposed) _ffi.dispose();
    });
  }

  Future<void> _drain() async {
    while (mounted && !_loadingSource && _pendingValue != null) {
      final v = _pendingValue!;
      _pendingValue = null;
      await _applyOnce(v);
    }
  }

  Future<void> _applyOnce(int value) async {
    final src = _sourceRgba;
    if (src == null) return;
    final res = _resolution;
    final sw = Stopwatch()..start();
    try {
      final Uint8List out;
      if (_transport == EditorTransport.channel) {
        final reply = await _channel.invokeMethod<Uint8List>('applyEffect', {
          'rgba': src,
          'width': res.width,
          'height': res.height,
          'effect': _effect.index,
          'value': value,
        });
        out = reply!;
        _bridgeBytes += src.length + out.length;
      } else {
        out = _ffi.apply(res.width, res.height, _effect.index, value);
      }
      final img = await _toImage(out, res.width, res.height);
      sw.stop();
      if (!mounted) {
        img.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = img;
        _lastApplyUs = sw.elapsedMicroseconds;
        _recentUs.add(_lastApplyUs);
        if (_recentUs.length > 30) _recentUs.removeAt(0);
      });
    } catch (e) {
      sw.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Apply failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<ui.Image> _toImage(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  void _togglePulse(bool on) {
    setState(() => _pulse = on);
    _pulseTimer?.cancel();
    _pulseTimer = null;
    if (on) {
      final t0 = DateTime.now();
      _pulseTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        if (!mounted) return;
        if (_loadingSource) return;
        final t = DateTime.now().difference(t0).inMilliseconds / 1000.0;
        final v = 50 + 50 * math.sin(2 * math.pi * t / 2.0);
        setState(() => _intensity = v);
        _enqueue(v.round());
      });
    }
  }

  double get _avgMs => _recentUs.isEmpty
      ? 0
      : _recentUs.reduce((a, b) => a + b) / _recentUs.length / 1000;

  @override
  Widget build(BuildContext context) {
    final avg = _avgMs;
    final fps = avg > 0 ? (1000 / avg).clamp(0, 999).toStringAsFixed(0) : '—';
    final isChannel = _transport == EditorTransport.channel;

    return Scaffold(
      appBar: AppBar(title: const Text('Live Editor'), centerTitle: true),
      body: Column(
        children: [
          if (kDebugMode)
            Container(
              width: double.infinity,
              color: Colors.red.shade900,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: const Text(
                '⚠ DEBUG BUILD — run in release/profile mode for honest latency.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _loadingSource
                ? const Center(child: CircularProgressIndicator())
                : (_image == null
                      ? const SizedBox.shrink()
                      : RawImage(image: _image, fit: BoxFit.contain)),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.black26,
            child: Text(
              'last ${(_lastApplyUs / 1000).toStringAsFixed(1)}ms'
              ' · avg ${avg.toStringAsFixed(1)}ms'
              ' · ~$fps fps'
              ' · bridge ${(_bridgeBytes / (1024 * 1024)).toStringAsFixed(0)} MB'
              '${isChannel ? '' : ' (zero-copy)'}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isChannel ? Colors.orangeAccent : Colors.greenAccent,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: SegmentedButton<EditorEffect>(
              segments: [
                for (final e in EditorEffect.values)
                  ButtonSegment(value: e, label: Text(e.label)),
              ],
              selected: {_effect},
              onSelectionChanged: (s) {
                setState(() => _effect = s.first);
                _enqueue(_intensity.round());
              },
            ),
          ),
          Slider(
            value: _intensity,
            min: 0,
            max: 100,
            onChanged: _pulse
                ? null
                : (v) {
                    setState(() => _intensity = v);
                    _enqueue(v.round());
                  },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<EditorTransport>(
                    segments: const [
                      ButtonSegment(
                        value: EditorTransport.channel,
                        label: Text('Channel'),
                      ),
                      ButtonSegment(
                        value: EditorTransport.ffi,
                        label: Text('FFI'),
                      ),
                    ],
                    selected: {_transport},
                    onSelectionChanged: (s) {
                      setState(() {
                        _transport = s.first;
                        _recentUs.clear();
                        _lastApplyUs = 0;
                      });
                      _enqueue(_intensity.round());
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<EditorResolution>(
                    segments: [
                      for (final r in EditorResolution.values)
                        ButtonSegment(value: r, label: Text(r.label)),
                    ],
                    selected: {_resolution},
                    onSelectionChanged: (s) {
                      setState(() {
                        _resolution = s.first;
                        _recentUs.clear();
                        _lastApplyUs = 0;
                      });
                      _loadSource();
                    },
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Pulse', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              '${_resolution.frameMB.toStringAsFixed(1)} MB/frame'
              '${isChannel ? ' × 2 over the bridge per tick' : ' — pixels stay native'}',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            value: _pulse,
            onChanged: _loadingSource ? null : _togglePulse,
            dense: true,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
