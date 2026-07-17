import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart' hide Timer, Matrix4;
import 'package:flame/game.dart' hide Matrix4;
import 'package:flame/particles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'camera_screen.dart';
import 'showcase_route.dart';

/// Showcase screen B — a live animated dashboard, all CustomPainter + Flame.
///
/// Everything runs off one ticker and streams forever (stage-safe).
/// Interactions: press & tilt any card (3D perspective), scrub the chart
/// for a crosshair readout, tap the Flame card for a particle burst.
class ShowcaseDashboardScreen extends StatefulWidget {
  const ShowcaseDashboardScreen({super.key});

  @override
  State<ShowcaseDashboardScreen> createState() =>
      _ShowcaseDashboardScreenState();
}

// Surface + series palette validated for dark mode (OKLCH band, CVD, contrast).
const _surface = Color(0xFF10141C);
const _series1 = Color(0xFF0095AE); // cyan — "Frames"
const _series2 = Color(0xFFC27C00); // amber — "Uploads"
const _accent = Color(0xFF00E5FF); // brand accent, never series identity
const _goodGreen = Color(0xFF34C069); // status, ships with an icon
const _badRed = Color(0xFFE05A5A); // status, ships with an icon
const _ink = Colors.white;

/// Layered sines → organic-looking live series in roughly 0..1.
double _stream(double x, double t, double seed) {
  return 0.5 +
      0.24 * math.sin(x * 5.2 + t * 1.1 + seed) +
      0.13 * math.sin(x * 11.0 - t * 1.9 + seed * 3.0) +
      0.07 * math.sin(x * 23.0 + t * 3.1 + seed * 7.0);
}

/// Shared clock: time + a per-frame repaint signal for every painter.
class _DashClock extends ChangeNotifier {
  double time = 0;
  void tick(double t) {
    time = t;
    notifyListeners();
  }
}

class _ShowcaseDashboardScreenState extends State<ShowcaseDashboardScreen>
    with TickerProviderStateMixin {
  late final Ticker _ticker;
  late final AnimationController _entrance;
  final _clock = _DashClock();
  final _game = _DashGame();
  final _scrub = ValueNotifier<double?>(null);

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _ticker = createTicker((elapsed) {
      _clock.tick(elapsed.inMicroseconds / 1e6);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _entrance.dispose();
    _scrub.dispose();
    super.dispose();
  }

  /// Eased entrance progress for the card at [index] (same curve the
  /// stagger wrapper uses) — painters read this to drive draw-on effects.
  double _entranceAt(int index) {
    final start = (index * 0.11).clamp(0.0, 0.5);
    return Curves.easeOutCubic
        .transform(((_entrance.value - start) / 0.5).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Drifting aurora blobs + dot grid, repainted by the clock.
          RepaintBoundary(
            child: CustomPaint(painter: _BackgroundPainter(clock: _clock)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _staggered(0, _buildHeader()),
                  const SizedBox(height: 10),
                  SizedBox(height: 92, child: _staggered(1, _buildKpiRow())),
                  const SizedBox(height: 12),
                  Expanded(flex: 5, child: _staggered(2, _buildChartCard())),
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 4,
                    child: Row(
                      children: [
                        Expanded(
                          child: _staggered(
                            3,
                            _GlassCard(
                              title: 'Frame rate',
                              clock: _clock,
                              shimmerPhase: 0.9,
                              child: CustomPaint(
                                painter: _GaugePainter(
                                  state: this,
                                  entranceIndex: 3,
                                  phase: 2.1,
                                  unit: 'fps',
                                  scaleMax: 120,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _staggered(
                            4,
                            _GlassCard(
                              title: 'Memory',
                              clock: _clock,
                              shimmerPhase: 1.8,
                              child: CustomPaint(
                                painter: _LiquidGaugePainter(
                                  state: this,
                                  entranceIndex: 4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 4,
                    child: Row(
                      children: [
                        Expanded(
                          child: _staggered(
                            5,
                            _GlassCard(
                              title: 'Jobs per hour',
                              clock: _clock,
                              shimmerPhase: 2.7,
                              child: CustomPaint(
                                painter: _BarsPainter(
                                  state: this,
                                  entranceIndex: 5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _staggered(
                            6,
                            _GlassCard(
                              title: 'Flame engine — tap me',
                              clock: _clock,
                              shimmerPhase: 3.6,
                              child: GestureDetector(
                                onTapDown: (d) => _game.burst(Vector2(
                                  d.localPosition.dx,
                                  d.localPosition.dy,
                                )),
                                child: GameWidget(game: _game),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _staggered(7, _buildFooterRow(context)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Slide-up + fade entrance, staggered by [index].
  Widget _staggered(int index, Widget child) {
    final start = (index * 0.11).clamp(0.0, 0.5);
    final anim = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 30 * (1 - anim.value)),
          child: child,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Everything animates. Everything is live.',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Charts, physics and a game engine — one Flutter code-base.',
                style: TextStyle(fontSize: 12, color: Colors.white60),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _LiveChip(clock: _clock),
      ],
    );
  }

  Widget _buildKpiRow() {
    return Row(
      children: [
        Expanded(
          child: _KpiTile(
            label: 'OPS / SEC',
            clock: _clock,
            seed: 0.7,
            min: 0.8e6,
            max: 1.6e6,
            period: const Duration(milliseconds: 1300),
            format: _fmtCompact,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiTile(
            label: 'P99 LATENCY',
            clock: _clock,
            seed: 3.9,
            min: 12,
            max: 42,
            period: const Duration(milliseconds: 1900),
            format: (v) => '${v.round()} ms',
            lowerIsBetter: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiTile(
            label: 'ACTIVE USERS',
            clock: _clock,
            seed: 8.2,
            min: 18e3,
            max: 32e3,
            period: const Duration(milliseconds: 2600),
            format: _fmtCompact,
          ),
        ),
      ],
    );
  }

  Widget _buildChartCard() {
    return _GlassCard(
      title: 'Live throughput — drag to inspect',
      clock: _clock,
      shimmerPhase: 0.0,
      tiltEnabled: false, // the chart owns its gesture: scrubbing
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => _scrub.value = d.localPosition.dx,
        onHorizontalDragUpdate: (d) => _scrub.value = d.localPosition.dx,
        onHorizontalDragEnd: (_) => _scrub.value = null,
        onHorizontalDragCancel: () => _scrub.value = null,
        child: CustomPaint(
          painter: _LineChartPainter(
            state: this,
            entranceIndex: 2,
            scrub: _scrub,
          ),
        ),
      ),
    );
  }

  Widget _buildFooterRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Flexible(
          child: Text(
            'Press & tilt the cards · scrub the chart',
            style: TextStyle(color: Colors.white38, fontSize: 11.5),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          onPressed: () => Navigator.of(context)
              .push(buildShowcaseRoute(const CameraScreen())),
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Next'),
        ),
      ],
    );
  }
}

String _fmtCompact(double v) {
  if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
  if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
  return v.toStringAsFixed(0);
}

// ---------- background ----------

/// Drifting, breathing aurora blobs + a faint dot grid.
class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter({required this.clock}) : super(repaint: clock);

  final _DashClock clock;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.time;

    void blob(Color color, Offset base, double r, double phase) {
      final c = base +
          Offset(
            34 * math.sin(t * 0.07 + phase),
            26 * math.cos(t * 0.09 + phase * 1.7),
          );
      final radius = r * (1 + 0.08 * math.sin(t * 0.13 + phase));
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(
            c,
            radius,
            [color, color.withValues(alpha: 0)],
          ),
      );
    }

    blob(_series1.withValues(alpha: 0.30), Offset(size.width * 0.12, 90),
        170, 0.0);
    blob(_series2.withValues(alpha: 0.16),
        Offset(size.width * 0.95, size.height * 0.72), 190, 2.4);
    blob(const Color(0xFF7A4FC7).withValues(alpha: 0.14),
        Offset(size.width * 0.55, size.height * 0.35), 150, 4.8);

    // Static dot grid, very recessive.
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.035);
    for (double y = 12; y < size.height; y += 26) {
      for (double x = 12; x < size.width; x += 26) {
        canvas.drawCircle(Offset(x, y), 1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) => false;
}

// ---------- header widgets ----------

/// "LIVE" chip with a pulsing dot.
class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.clock});

  final _DashClock clock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(10, 10),
            painter: _PulseDotPainter(clock: clock),
          ),
          const SizedBox(width: 5),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDotPainter extends CustomPainter {
  _PulseDotPainter({required this.clock}) : super(repaint: clock);

  final _DashClock clock;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = (clock.time * 0.8) % 1.0;
    canvas.drawCircle(
      c,
      2.2 + 3.2 * p,
      Paint()..color = _accent.withValues(alpha: 0.5 * (1 - p)),
    );
    canvas.drawCircle(c, 2.4, Paint()..color = _accent);
  }

  @override
  bool shouldRepaint(_PulseDotPainter oldDelegate) => false;
}

// ---------- KPI tiles ----------

class _KpiTile extends StatefulWidget {
  const _KpiTile({
    required this.label,
    required this.clock,
    required this.seed,
    required this.min,
    required this.max,
    required this.period,
    required this.format,
    this.lowerIsBetter = false,
  });

  final String label;
  final _DashClock clock;
  final double seed;
  final double min;
  final double max;
  final Duration period;
  final String Function(double) format;
  final bool lowerIsBetter;

  @override
  State<_KpiTile> createState() => _KpiTileState();
}

class _KpiTileState extends State<_KpiTile> {
  Timer? _timer;
  double? _prev;
  late double _value = _sample();

  double _sample() {
    final t = widget.clock.time;
    final s = _stream(t * 0.06, t, widget.seed).clamp(0.0, 1.0);
    return widget.min + (widget.max - widget.min) * s;
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.period, (_) {
      setState(() {
        _prev = _value;
        _value = _sample();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prev = _prev;
    final pct = prev == null || prev == 0 ? 0.0 : (_value - prev) / prev * 100;
    final isGood = widget.lowerIsBetter ? pct < 0 : pct > 0;
    final statusColor = isGood ? _goodGreen : _badRed;

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 3),
          _RollingText(
            text: widget.format(_value),
            style: const TextStyle(
              color: _ink,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          Row(
            children: [
              if (prev != null) ...[
                Icon(
                  pct >= 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 16,
                  color: statusColor,
                ),
                Text(
                  '${pct.abs().toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: 52,
                height: 18,
                child: CustomPaint(
                  painter: _SparklinePainter(
                    clock: widget.clock,
                    seed: widget.seed,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Odometer-style text: each character rolls in from below when it changes.
class _RollingText extends StatelessWidget {
  const _RollingText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < text.length; i++)
          ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 340),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.7),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: Text(
                text[i],
                key: ValueKey('$i-${text[i]}'),
                style: style,
              ),
            ),
          ),
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.clock, required this.seed})
      : super(repaint: clock);

  final _DashClock clock;
  final double seed;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.time;
    const n = 22;
    final path = Path();
    late Offset last;
    for (var i = 0; i <= n; i++) {
      final f = i / n;
      final v = _stream((t * 0.06) - 0.4 * (1 - f), t, seed).clamp(0.0, 1.0);
      final p = Offset(f * size.width, size.height * (0.9 - 0.8 * v));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      last = p;
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = _series1,
    );
    canvas.drawCircle(last, 2, Paint()..color = _series1);
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) => false;
}

// ---------- glass card with 3D tilt + shimmer ----------

/// Frosted card. Press anywhere → it tilts toward your finger in 3D
/// perspective and scales up; release → elastic spring back. A shimmer
/// highlight sweeps across every few seconds.
class _GlassCard extends StatefulWidget {
  const _GlassCard({
    required this.title,
    required this.child,
    required this.clock,
    this.shimmerPhase = 0,
    this.tiltEnabled = true,
  });

  final String title;
  final Widget child;
  final _DashClock clock;
  final double shimmerPhase;
  final bool tiltEnabled;

  @override
  State<_GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<_GlassCard> {
  Offset _tilt = Offset.zero; // normalized -1..1 in both axes
  bool _pressed = false;

  void _updateTilt(Offset local, Size size) {
    setState(() {
      _pressed = true;
      _tilt = Offset(
        ((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0),
        ((local.dy / size.height) * 2 - 1).clamp(-1.0, 1.0),
      );
    });
  }

  void _release() {
    setState(() {
      _pressed = false;
      _tilt = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(child: SizedBox.expand(child: widget.child)),
            ],
          ),
        ),
      ),
    );

    // Shimmer overlay + card, then the animated 3D transform.
    final content = Stack(
      fit: StackFit.passthrough,
      children: [
        card,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CustomPaint(
                painter: _ShimmerPainter(
                  clock: widget.clock,
                  phase: widget.shimmerPhase,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final animated = TweenAnimationBuilder<Offset>(
      tween: Tween(end: _tilt),
      duration: _pressed
          ? const Duration(milliseconds: 40)
          : const Duration(milliseconds: 600),
      curve: _pressed ? Curves.linear : Curves.elasticOut,
      builder: (context, tilt, child) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0016)
          ..rotateX(-tilt.dy * 0.10)
          ..rotateY(tilt.dx * 0.12),
        child: child,
      ),
      child: AnimatedScale(
        scale: _pressed ? 1.035 : 1.0,
        duration: const Duration(milliseconds: 450),
        curve: _pressed ? Curves.easeOutCubic : Curves.elasticOut,
        child: content,
      ),
    );

    if (!widget.tiltEnabled) return animated;

    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onPanDown: (d) => _updateTilt(d.localPosition, constraints.biggest),
        onPanUpdate: (d) => _updateTilt(d.localPosition, constraints.biggest),
        onPanEnd: (_) => _release(),
        onPanCancel: _release,
        child: animated,
      ),
    );
  }
}

/// Diagonal highlight that sweeps across the card every few seconds.
class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter({required this.clock, required this.phase})
      : super(repaint: clock);

  final _DashClock clock;
  final double phase;

  static const _period = 4.6;
  static const _window = 0.9;

  @override
  void paint(Canvas canvas, Size size) {
    final cycle = (clock.time + phase) % _period;
    if (cycle > _window) return;
    final p = cycle / _window;
    final x = ui.lerpDouble(-size.width * 0.4, size.width * 1.4, p)!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(x - 90, 0),
          Offset(x + 90, size.height * 0.5),
          [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.055),
            Colors.white.withValues(alpha: 0),
          ],
          [0.0, 0.5, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_ShimmerPainter oldDelegate) => false;
}

// ---------- line chart ----------

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.state,
    required this.entranceIndex,
    required this.scrub,
  }) : super(repaint: Listenable.merge([state._clock, scrub]));

  final _ShowcaseDashboardScreenState state;
  final int entranceIndex;
  final ValueNotifier<double?> scrub;

  static const _labelGutter = 64.0;
  static const _n = 70;

  @override
  void paint(Canvas canvas, Size size) {
    final t = state._clock.time;
    final e = state._entranceAt(entranceIndex);
    final plotW = size.width - _labelGutter;

    // Recessive grid.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(plotW, y), grid);
    }

    _drawSeries(canvas, size, plotW, t, e, _series1, 0.0, 'Frames');
    _drawSeries(canvas, size, plotW, t, e, _series2, 4.7, 'Uploads');
    _drawScrub(canvas, size, plotW, t);
  }

  Offset _point(Size size, double plotW, double t, double seed, double fx) {
    final v = _stream(fx + t * 0.06, t, seed);
    return Offset(fx * plotW, size.height * (0.92 - 0.8 * v));
  }

  void _drawSeries(Canvas canvas, Size size, double plotW, double t, double e,
      Color color, double seed, String name) {
    final path = Path();
    late Offset last;
    for (var i = 0; i <= _n; i++) {
      final p = _point(size, plotW, t, seed, i / _n);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      last = p;
    }

    // Gradient area fill, revealed left→right with the entrance.
    final area = Path.from(path)
      ..lineTo(plotW, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, plotW * e, size.height));
    canvas.drawPath(
      area,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [color.withValues(alpha: 0.16), color.withValues(alpha: 0)],
        ),
    );
    canvas.restore();

    // Draw-on entrance: trace the path, then a soft glow + crisp stroke.
    final metric = path.computeMetrics().first;
    final visible = metric.extractPath(0, metric.length * e);
    canvas.drawPath(
      visible,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.13),
    );
    canvas.drawPath(
      visible,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    if (e > 0.98) {
      // Pulsing "live" head dot.
      final pulse = 0.5 + 0.5 * math.sin(t * 5 + seed);
      canvas.drawCircle(last, 5.5 + 2.5 * pulse,
          Paint()..color = color.withValues(alpha: 0.25 * (1 - pulse * 0.5)));
      canvas.drawCircle(last, 3.4, Paint()..color = color);
      canvas.drawCircle(last, 1.5, Paint()..color = _ink);

      // Direct label at the line end: colored chip + text in ink.
      final tp = _text(name, const TextStyle(
        color: Colors.white70,
        fontSize: 11,
      ));
      final ly =
          (last.dy - tp.height / 2).clamp(0.0, size.height - tp.height);
      canvas.drawCircle(Offset(plotW + 10, ly + tp.height / 2), 3.5,
          Paint()..color = color);
      tp.paint(canvas, Offset(plotW + 17, ly));
    }
  }

  void _drawScrub(Canvas canvas, Size size, double plotW, double t) {
    final x = scrub.value;
    if (x == null || x < 0 || x > plotW) return;
    final fx = x / plotW;

    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..strokeWidth = 1,
    );

    final entries = [
      ('Frames', _series1, 0.0),
      ('Uploads', _series2, 4.7),
    ];

    // Rings on each series (2px surface ring, per mark spec).
    final values = <(String, Color, double, Offset)>[];
    for (final (name, color, seed) in entries) {
      final p = _point(size, plotW, t, seed, fx);
      final v = (_stream(fx + t * 0.06, t, seed) * 100).round().toDouble();
      values.add((name, color, v, p));
      canvas.drawCircle(p, 5.5, Paint()..color = _surface);
      canvas.drawCircle(
        p,
        4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = color,
      );
    }

    // Readout chip near the top of the crosshair.
    final rows = [
      for (final (name, color, v, _) in values)
        (color, _text('$name  ${v.round()}', const TextStyle(
          color: _ink,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ))),
    ];
    final chipW =
        rows.map((r) => r.$2.width).reduce(math.max) + 26;
    const rowH = 16.0;
    final chipH = rows.length * rowH + 12;
    var cx = x + 10;
    if (cx + chipW > plotW) cx = x - 10 - chipW;
    final chipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx, 4, chipW, chipH),
      const Radius.circular(8),
    );
    canvas.drawRRect(
        chipRect, Paint()..color = _surface.withValues(alpha: 0.92));
    canvas.drawRRect(
      chipRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white.withValues(alpha: 0.15),
    );
    for (var i = 0; i < rows.length; i++) {
      final y = 10 + i * rowH;
      canvas.drawCircle(
          Offset(cx + 12, y + 5), 3.2, Paint()..color = rows[i].$1);
      rows[i].$2.paint(canvas, Offset(cx + 20, y));
    }
  }

  TextPainter _text(String s, TextStyle style) => TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  bool shouldRepaint(_LineChartPainter oldDelegate) => false;
}

// ---------- gauges ----------

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.state,
    required this.entranceIndex,
    required this.phase,
    required this.unit,
    required this.scaleMax,
  }) : super(repaint: state._clock);

  final _ShowcaseDashboardScreenState state;
  final int entranceIndex;
  final double phase;
  final String unit;
  final int scaleMax;

  double _value01(double t) => (0.72 +
          0.18 * math.sin(t * 0.5 + phase) +
          0.06 * math.sin(t * 1.7 + phase * 2))
      .clamp(0.05, 0.98);

  @override
  void paint(Canvas canvas, Size size) {
    final t = state._clock.time;
    final e = state._entranceAt(entranceIndex);
    final v = _value01(t) * e;
    final value = (v * scaleMax).round();

    final center = Offset(size.width / 2, size.height * 0.56);
    final r = math.min(size.width, size.height) * 0.40;
    const startA = math.pi * 0.78;
    const sweepA = math.pi * 1.44;

    // Tick ring.
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.4;
    for (var i = 0; i <= 24; i++) {
      final a = startA + sweepA * i / 24;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
          center + dir * (r + 7), center + dir * (r + 11), tick);
    }

    // Track.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      startA,
      sweepA,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.08),
    );

    // Value arc with a single-hue light→dark sweep.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      startA,
      sweepA * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.sweep(
          center,
          const [Color(0xFF045668), _series1, Color(0xFF66D9EC)],
          const [0.0, 0.6, 1.0],
          TileMode.clamp,
          startA,
          startA + sweepA,
        ),
    );

    // Peak-hold marker (VU-meter style): max over the last ~2.5 s.
    if (e > 0.9) {
      var peak = 0.0;
      for (var k = 0; k < 25; k++) {
        peak = math.max(peak, _value01(t - k * 0.1));
      }
      final pa = startA + sweepA * peak;
      final pd = Offset(math.cos(pa), math.sin(pa));
      canvas.drawCircle(
          center + pd * r, 3, Paint()..color = Colors.white.withValues(alpha: 0.85));
    }

    // Value in ink (text tokens), never the series color.
    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$value',
            style: const TextStyle(
              color: _ink,
              fontSize: 25,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(
            text: ' $unit',
            style: const TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) => false;
}

/// Liquid-fill gauge: animated sine waves inside a circle + rising bubbles.
class _LiquidGaugePainter extends CustomPainter {
  _LiquidGaugePainter({required this.state, required this.entranceIndex})
      : super(repaint: state._clock);

  final _ShowcaseDashboardScreenState state;
  final int entranceIndex;

  double _level(double t) => (0.48 +
          0.20 * math.sin(t * 0.21 + 1.3) +
          0.05 * math.sin(t * 0.83))
      .clamp(0.08, 0.95);

  @override
  void paint(Canvas canvas, Size size) {
    final t = state._clock.time;
    final e = state._entranceAt(entranceIndex);
    final level = _level(t) * e;

    final c = Offset(size.width / 2, size.height * 0.52);
    final r = math.min(size.width, size.height) * 0.40;

    // Outline ring.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.14),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r - 2)));

    final levelY = c.dy + r - 2 * r * level;

    Path wave(double amp, double speed, double ph, double k) {
      final path = Path()..moveTo(c.dx - r, c.dy + r + 4);
      for (var x = -r; x <= r; x += r / 16) {
        final y =
            levelY + amp * math.sin((x / r) * k + t * speed + ph);
        path.lineTo(c.dx + x, y);
      }
      return path
        ..lineTo(c.dx + r, c.dy + r + 4)
        ..close();
    }

    // Back wave (lighter) + front wave (gradient fill).
    canvas.drawPath(
      wave(4.2, 1.6, 1.9, 5.1),
      Paint()..color = _series1.withValues(alpha: 0.35),
    );
    canvas.drawPath(
      wave(3.4, 2.3, 0.0, 4.2),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(c.dx, levelY),
          Offset(c.dx, c.dy + r),
          [_series1.withValues(alpha: 0.85), const Color(0xFF045668)],
        ),
    );

    // Rising bubbles inside the liquid.
    for (var i = 0; i < 4; i++) {
      final u = ((t * 0.22 + i * 0.29) % 1.0);
      final bx = c.dx + math.sin(t * 1.1 + i * 2.3) * r * 0.35;
      final by = ui.lerpDouble(c.dy + r - 8, levelY + 8, u)!;
      if (by > levelY) {
        canvas.drawCircle(
          Offset(bx, by),
          1.4 + i * 0.5,
          Paint()..color = Colors.white.withValues(alpha: 0.28 * (1 - u)),
        );
      }
    }
    canvas.restore();

    // Percent in ink, centered.
    final tp = TextPainter(
      text: TextSpan(
        text: '${(level * 100).round()}%',
        style: const TextStyle(
          color: _ink,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
          shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_LiquidGaugePainter oldDelegate) => false;
}

// ---------- bars ----------

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.state, required this.entranceIndex})
      : super(repaint: state._clock);

  final _ShowcaseDashboardScreenState state;
  final int entranceIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final t = state._clock.time;
    final e = state._entranceAt(entranceIndex);
    const n = 9;
    final slot = size.width / n;
    final barW = slot - 6; // ≥2px surface gap between bars

    var maxV = 0.0;
    var maxI = 0;
    final heights = List<double>.generate(n, (i) {
      final v = 0.25 +
          0.65 *
              (0.5 +
                      0.5 *
                          math.sin(t * 0.6 + i * 1.7) *
                          math.sin(t * 0.23 + i * 0.9))
                  .clamp(0.0, 1.0);
      if (v > maxV) {
        maxV = v;
        maxI = i;
      }
      return v;
    });

    for (var i = 0; i < n; i++) {
      // Staggered grow-in.
      final ei = Curves.easeOutBack
          .transform(((e * 1.6) - i * 0.07).clamp(0.0, 1.0));
      final h = size.height * heights[i] * ei * 0.88;
      if (h <= 0) continue;
      final x = i * slot + 3;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, size.height - h, barW, h),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x, size.height - h),
            Offset(x, size.height),
            [_series1, const Color(0xFF045668)],
          ),
      );

      // Moving sheen sweeping across the bars.
      final sweep = ((t * 0.35) % 1.6) * n - 1;
      final d = (i - sweep).abs();
      if (d < 1.2) {
        canvas.drawRRect(
          rect,
          Paint()..color = Colors.white.withValues(alpha: 0.10 * (1.2 - d)),
        );
      }
    }

    // Selective direct label: value on the current tallest bar only.
    if (e > 0.95) {
      final h = size.height * heights[maxI] * 0.88;
      final tp = TextPainter(
        text: TextSpan(
          text: '${(maxV * 520).round()}',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (maxI * slot + 3 + barW / 2 - tp.width / 2)
              .clamp(0.0, size.width - tp.width),
          math.max(0, size.height - h - tp.height - 3),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) => false;
}

// ---------- Flame engine card ----------

/// Tiny Flame game embedded in a dashboard card: a procedurally-drawn
/// character that bounces with squash & stretch, leaves a motion trail,
/// blinks, somersaults on hops, and explodes particles on tap.
/// No sprites, no assets — pure Canvas.
class _DashGame extends FlameGame {
  final _rng = math.Random();
  _Bouncer? _bouncer;
  double _sparkleTimer = 0;

  @override
  Color backgroundColor() => const Color(0x00000000); // glass shows through

  @override
  Future<void> onLoad() async {
    add(_Trail());
    _bouncer = _Bouncer();
    add(_bouncer!);
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Ambient sparkles drifting up through the card.
    _sparkleTimer -= dt;
    if (_sparkleTimer <= 0 && size.x > 0) {
      _sparkleTimer = 0.35 + _rng.nextDouble() * 0.3;
      add(
        ParticleSystemComponent(
          position: Vector2(_rng.nextDouble() * size.x, size.y - 2),
          particle: AcceleratedParticle(
            lifespan: 1.6,
            speed: Vector2(
              (_rng.nextDouble() - 0.5) * 14,
              -22 - _rng.nextDouble() * 30,
            ),
            child: CircleParticle(
              radius: 0.9 + _rng.nextDouble() * 1.1,
              paint: Paint()
                ..color = Colors.white.withValues(alpha: 0.22),
            ),
          ),
        ),
      );
    }
  }

  void burst(Vector2 at) {
    add(
      ParticleSystemComponent(
        position: at,
        particle: Particle.generate(
          count: 24,
          lifespan: 0.8,
          generator: (i) {
            final a = _rng.nextDouble() * math.pi * 2;
            final speed = 50 + _rng.nextDouble() * 150;
            return AcceleratedParticle(
              speed: Vector2(math.cos(a), math.sin(a)) * speed,
              acceleration: Vector2(0, 260),
              child: CircleParticle(
                radius: 1.5 + _rng.nextDouble() * 2.2,
                paint: Paint()
                  ..color =
                      (i.isEven ? _accent : _series2).withValues(alpha: 0.9),
              ),
            );
          },
        ),
      ),
    );
    _bouncer?.hop(big: true);
  }
}

/// Fading ghost trail behind the bouncer (rendered beneath it).
class _Trail extends Component with HasGameReference<_DashGame> {
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final pts = game._bouncer?.trail;
    if (pts == null || pts.length < 2) return;
    for (var i = 0; i < pts.length; i++) {
      final f = (i + 1) / pts.length;
      canvas.drawCircle(
        pts[i],
        4 + 11 * f,
        Paint()..color = _accent.withValues(alpha: 0.13 * f),
      );
    }
  }
}

class _Bouncer extends PositionComponent with HasGameReference<_DashGame> {
  static const _gravity = 520.0;
  static const _bounceV = 190.0;
  static const _hopV = 260.0;
  static const _bigHopV = 330.0;
  static const _groundPad = 4.0;

  double _vx = 62;
  double _vy = 0;
  double _squash = 0; // 1 right after landing, decays to 0
  double _flip = 0; // 0 = idle; (0,1] = somersault in progress
  double _flipDir = 1;
  double _blink = 0; // >0 while the eyes are closed
  double _nextBlink = 2.4;
  double _nextAutoHop = 3.5;

  final List<Offset> trail = [];

  @override
  Future<void> onLoad() async {
    size = Vector2.all(44);
    anchor = Anchor.bottomCenter;
    position = Vector2(game.size.x * 0.3, game.size.y - _groundPad);
  }

  void hop({bool big = false}) {
    _vy = -(big ? _bigHopV : _hopV);
    _squash = 1;
    _flip = 0.001;
    _flipDir = _vx >= 0 ? 1 : -1;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final bounds = game.size;
    if (bounds.x <= 0 || bounds.y <= 0) return;

    _vy += _gravity * dt;
    position.y += _vy * dt;
    position.x += _vx * dt;

    // Walls.
    final halfW = size.x / 2;
    if (position.x < halfW) {
      position.x = halfW;
      _vx = _vx.abs();
    } else if (position.x > bounds.x - halfW) {
      position.x = bounds.x - halfW;
      _vx = -_vx.abs();
    }

    // Ground bounce with squash + dust.
    final ground = bounds.y - _groundPad;
    final onGround = position.y >= ground - 0.5;
    if (position.y >= ground && _vy > 0) {
      position.y = ground;
      _vy = -_bounceV;
      _squash = 1;
      _dust();
    }

    // Occasional self-hop with a somersault.
    _nextAutoHop -= dt;
    if (_nextAutoHop <= 0 && onGround) {
      _nextAutoHop = 3 + game._rng.nextDouble() * 3;
      hop();
    }

    // Blinking.
    if (_blink > 0) {
      _blink = math.max(0, _blink - dt);
    } else {
      _nextBlink -= dt;
      if (_nextBlink <= 0) {
        _nextBlink = 2 + game._rng.nextDouble() * 2.5;
        _blink = 0.12;
      }
    }

    // Somersault progress.
    if (_flip > 0) {
      _flip += dt / 0.55;
      if (_flip >= 1) _flip = 0;
    }

    _squash = math.max(0, _squash - dt * 5);
    // Squash on landing, slight stretch while rising fast.
    final stretch = (-_vy / 900).clamp(0.0, 0.25);
    scale.setValues(
      1 + 0.30 * _squash - stretch,
      1 - 0.30 * _squash + stretch,
    );

    // Motion trail (body-center points, in game coords).
    final center =
        Offset(position.x, position.y - size.y / 2 * scale.y);
    if (trail.isEmpty || (trail.last - center).distance > 3) {
      trail.add(center);
      if (trail.length > 14) trail.removeAt(0);
    }
  }

  void _dust() {
    final rng = game._rng;
    game.add(
      ParticleSystemComponent(
        position: position.clone(),
        particle: Particle.generate(
          count: 6,
          lifespan: 0.4,
          generator: (i) => AcceleratedParticle(
            speed: Vector2(
              (rng.nextDouble() - 0.5) * 120,
              -20 - rng.nextDouble() * 40,
            ),
            acceleration: Vector2(0, 160),
            child: CircleParticle(
              radius: 1.2 + rng.nextDouble() * 1.4,
              paint: Paint()..color = Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final c = Offset(size.x / 2, size.y / 2);
    const r = 17.0;
    final facing = _vx >= 0 ? 1.0 : -1.0;

    // Somersault: rotate the whole body around its center.
    canvas.save();
    if (_flip > 0) {
      final a = Curves.easeInOut.transform(_flip) * math.pi * 2 * _flipDir;
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a);
      canvas.translate(-c.dx, -c.dy);
    }

    // Glow halo.
    canvas.drawCircle(
        c, r + 8, Paint()..color = _accent.withValues(alpha: 0.14));

    // Body with a soft top-light gradient.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c - const Offset(5, 7),
          r * 2.1,
          [const Color(0xFF7FF3FF), _series1, const Color(0xFF045668)],
          [0.0, 0.55, 1.0],
        ),
    );

    // Eyes look where it's going; they blink.
    final eyeH = _blink > 0 ? 1.4 : 9.2;
    final eyeY = c.dy - 4;
    for (final ex in [-6.5, 6.5]) {
      final eye = Offset(c.dx + ex + 2 * facing, eyeY);
      canvas.drawOval(
        Rect.fromCenter(center: eye, width: 9.2, height: eyeH),
        Paint()..color = Colors.white,
      );
      if (_blink <= 0) {
        canvas.drawCircle(
          eye + Offset(1.6 * facing, 0.4),
          2.2,
          Paint()..color = const Color(0xFF0B1020),
        );
      }
    }

    // Smile.
    canvas.drawArc(
      Rect.fromCircle(center: c + const Offset(0, 4), radius: 6),
      0.35,
      math.pi - 0.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF0B1020),
    );

    canvas.restore();
  }
}
