import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'showcase_dashboard_screen.dart';
import 'showcase_route.dart';

/// Showcase screen A — a ray-traced 3D solar system rendered by a single
/// fragment shader, with a CPU-driven parallax particle field composited
/// on top.
///
/// Idle: cinematic auto-orbit. Drag: swing the camera AND attract the
/// particles to your finger. Pinch: zoom. Double-tap: particle warp kick.
class ShowcaseSolarScreen extends StatefulWidget {
  const ShowcaseSolarScreen({super.key});

  @override
  State<ShowcaseSolarScreen> createState() => _ShowcaseSolarScreenState();
}

class _ShowcaseSolarScreenState extends State<ShowcaseSolarScreen>
    with SingleTickerProviderStateMixin {
  /// Drop to 0.75 if the demo phone can't hold 60 fps at native res — the
  /// shader then renders into a smaller layer that FittedBox scales up.
  /// Verify the win with the performance overlay before relying on it.
  static const double _renderScale = 1.0;

  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  final _repaint = _TickNotifier();

  // Camera.
  double _time = 0;
  double _yaw = 0.6;
  double _pitch = 0.22;
  double _dist = 5.2;
  double _distAtPinchStart = 5.2;
  bool _touching = false;

  // Particles.
  final List<_Particle> _particles = [];
  final List<_Ripple> _ripples = [];
  Offset? _well; // finger position = gravity well
  Size _fieldSize = Size.zero;
  double _prevYaw = 0.6;
  final _rng = math.Random(42);

  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadShader();
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _loadShader() async {
    final program =
        await ui.FragmentProgram.fromAsset('shaders/solar_system.frag');
    if (!mounted) return;
    setState(() => _shader = program.fragmentShader());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt =
        ((elapsed - _lastElapsed).inMicroseconds / 1e6).clamp(0.0, 1 / 20);
    _lastElapsed = elapsed;
    _time = elapsed.inMicroseconds / 1e6;

    if (!_touching) {
      // Cinematic auto-orbit; pitch eases back to its resting angle.
      _yaw += dt * 0.07;
      _pitch += (0.22 - _pitch) * dt * 0.4;
    }
    _updateParticles(dt);
    _ripples.removeWhere((r) => _time - r.start > _Ripple.life);
    _repaint.tick();
  }

  // ---------- particles ----------

  void _seedParticles(Size size) {
    _fieldSize = size;
    _particles.clear();
    for (var i = 0; i < 190; i++) {
      final z = 0.35 + _rng.nextDouble() * 0.65; // depth: 0.35 far … 1 near
      final hue = _rng.nextDouble();
      final color = hue < 0.65
          ? const Color(0xFF00E5FF)
          : hue < 0.85
              ? const Color(0xFF9BE8FF)
              : const Color(0xFF7A6CFF);
      _particles.add(_Particle(
        pos: Offset(
          _rng.nextDouble() * size.width,
          _rng.nextDouble() * size.height,
        ),
        vel: Offset.zero,
        seed: _rng.nextDouble() * math.pi * 2,
        z: z,
        color: color,
        size: 0.8 + _rng.nextDouble() * 0.6,
        twinkle: 1.5 + _rng.nextDouble() * 2.5,
      ));
    }
  }

  void _updateParticles(double dt) {
    final size = _fieldSize;
    if (size == Size.zero) return;
    // Parallax: camera yaw slides near layers more than far ones. Applied
    // in the physics step so the gravity well stays under the finger.
    final yawDelta = _yaw - _prevYaw;
    _prevYaw = _yaw;
    for (final p in _particles) {
      p.pos += Offset(yawDelta * 90.0 * p.z, 0);
      // Sine flow field for organic drift; far layers drift slower.
      final a = math.sin(p.pos.dx * 0.006 + _time * 0.4 + p.seed) +
          math.cos(p.pos.dy * 0.005 - _time * 0.3);
      var target = Offset(math.cos(a), math.sin(a)) * (10.0 + 18.0 * p.z);

      // Finger gravity well.
      final well = _well;
      if (well != null) {
        final d = well - p.pos;
        final dist = d.distance;
        if (dist > 1) {
          final pull = (240.0 - dist).clamp(0.0, 240.0) / 240.0;
          target += (d / dist) * pull * 260.0;
        }
      }

      p.vel += (target - p.vel) * (dt * 2.2);
      p.pos += p.vel * dt;

      // Wrap around the edges.
      if (p.pos.dx < -10) p.pos = Offset(size.width + 10, p.pos.dy);
      if (p.pos.dx > size.width + 10) p.pos = Offset(-10, p.pos.dy);
      if (p.pos.dy < -10) p.pos = Offset(p.pos.dx, size.height + 10);
      if (p.pos.dy > size.height + 10) p.pos = Offset(p.pos.dx, -10);
    }
  }

  void _warpKick(Offset center) {
    for (final p in _particles) {
      final d = p.pos - center;
      final dist = math.max(d.distance, 1.0);
      final impulse = 950.0 * math.exp(-dist / 170.0);
      p.vel += (d / dist) * impulse;
    }
    _ripples.add(_Ripple(center: center, start: _time));
  }

  // ---------- gestures ----------

  void _onScaleStart(ScaleStartDetails d) {
    _touching = true;
    _distAtPinchStart = _dist;
    _well = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    _well = d.localFocalPoint;
    _yaw -= d.focalPointDelta.dx * 0.008;
    _pitch =
        (_pitch + d.focalPointDelta.dy * 0.006).clamp(-1.25, 1.25);
    if (d.pointerCount > 1) {
      _dist = (_distAtPinchStart / d.scale).clamp(3.0, 9.0);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _touching = false;
    _well = null;
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (_fieldSize != size) _seedParticles(size);
          return GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            onDoubleTapDown: (d) => _warpKick(d.localPosition),
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(child: _buildShaderLayer(size)),
                RepaintBoundary(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ParticlePainter(
                        state: this,
                        repaint: _repaint,
                      ),
                    ),
                  ),
                ),
                _buildTitleCard(),
                _buildNextButton(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildShaderLayer(Size size) {
    final paint = _shader == null
        ? const ColoredBox(color: Colors.black)
        : CustomPaint(
            painter: _SolarPainter(
              shader: _shader!,
              state: this,
              repaint: _repaint,
            ),
          );
    if (_renderScale == 1.0) return paint;
    // Render-scale fallback: paint into a smaller layer, upscale to fit.
    return FittedBox(
      fit: BoxFit.fill,
      child: SizedBox(
        width: size.width * _renderScale,
        height: size.height * _renderScale,
        child: paint,
      ),
    );
  }

  Widget _buildTitleCard() {
    return Positioned(
      top: 64,
      left: 24,
      right: 24,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Stack(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Flutter can do this.',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'A ray-traced 3D scene + live particles — one GLSL '
                      'file, no game engine. Drag to orbit · pinch to zoom '
                      '· double-tap to warp.',
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              // Slow sheen so the card never looks static.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SheenPainter(state: this, repaint: _repaint),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNextButton(BuildContext context) {
    return Positioned(
      bottom: 40,
      right: 24,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF00E5FF),
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        onPressed: () => Navigator.of(context).push(
          buildShowcaseRoute(const ShowcaseDashboardScreen()),
        ),
        icon: const Icon(Icons.arrow_forward),
        label: const Text('Next'),
      ),
    );
  }
}

class _TickNotifier extends ChangeNotifier {
  void tick() => notifyListeners();
}

class _Particle {
  _Particle({
    required this.pos,
    required this.vel,
    required this.seed,
    required this.z,
    required this.color,
    required this.size,
    required this.twinkle,
  });

  Offset pos;
  Offset vel;
  final double seed;
  final double z; // depth: 0.35 (far) … 1.0 (near)
  final Color color;
  final double size;
  final double twinkle;
}

class _Ripple {
  _Ripple({required this.center, required this.start});

  static const life = 0.7; // seconds

  final Offset center;
  final double start;
}

/// Full-screen fragment-shader pass: the raymarched solar system.
class _SolarPainter extends CustomPainter {
  _SolarPainter({
    required this.shader,
    required this.state,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ui.FragmentShader shader;
  final _ShowcaseSolarScreenState state;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, state._time)
      ..setFloat(3, state._yaw)
      ..setFloat(4, state._pitch)
      ..setFloat(5, state._dist);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_SolarPainter oldDelegate) => false; // repaint drives it
}

/// CPU particle overlay: layered stardust with yaw parallax, twinkle,
/// constellation lines, and warp ripples on double-tap.
class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.state, required Listenable repaint})
      : super(repaint: repaint);

  final _ShowcaseSolarScreenState state;

  static const _linkDist = 78.0;

  @override
  void paint(Canvas canvas, Size size) {
    final particles = state._particles;
    if (particles.isEmpty) return;
    final t = state._time;

    // Constellation lines, faded by the deeper endpoint.
    final line = Paint()..strokeWidth = 0.8;
    for (var i = 0; i < particles.length; i++) {
      final a = particles[i].pos;
      for (var j = i + 1; j < particles.length; j++) {
        final b = particles[j].pos;
        final dx = a.dx - b.dx, dy = a.dy - b.dy;
        final d2 = dx * dx + dy * dy;
        if (d2 < _linkDist * _linkDist) {
          final depth = math.min(particles[i].z, particles[j].z);
          final alpha = (1.0 - math.sqrt(d2) / _linkDist) * 0.20 * depth;
          line.color = particles[i].color.withValues(alpha: alpha);
          canvas.drawLine(a, b, line);
        }
      }
    }

    // Dots with glow, twinkling; near particles are bigger and brighter.
    final glow = Paint();
    final dot = Paint();
    for (final p in particles) {
      final tw = 0.55 + 0.45 * math.sin(t * p.twinkle + p.seed * 10);
      glow.color = p.color.withValues(alpha: 0.10 * tw * p.z);
      dot.color = p.color.withValues(alpha: 0.85 * tw);
      canvas.drawCircle(p.pos, (2.5 + 4.5 * p.z) * p.size, glow);
      canvas.drawCircle(p.pos, (0.9 + 1.1 * p.z) * p.size, dot);
    }

    // Warp ripples.
    for (final r in state._ripples) {
      final f = ((t - r.start) / _Ripple.life).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(f);
      canvas.drawCircle(
        r.center,
        20 + 380 * eased,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - f) + 0.5
          ..color = const Color(0xFF00E5FF).withValues(alpha: 0.35 * (1 - f)),
      );
      canvas.drawCircle(
        r.center,
        10 + 240 * eased,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.18 * (1 - f)),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) => false;
}

/// Slow diagonal sheen sweeping across the title card every few seconds.
class _SheenPainter extends CustomPainter {
  _SheenPainter({required this.state, required Listenable repaint})
      : super(repaint: repaint);

  final _ShowcaseSolarScreenState state;

  static const _period = 5.2;
  static const _window = 1.1;

  @override
  void paint(Canvas canvas, Size size) {
    final cycle = state._time % _period;
    if (cycle > _window) return;
    final p = cycle / _window;
    final x = ui.lerpDouble(-size.width * 0.4, size.width * 1.4, p)!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(x - 70, 0),
          Offset(x + 70, size.height),
          [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0),
          ],
          [0.0, 0.5, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_SheenPainter oldDelegate) => false;
}
