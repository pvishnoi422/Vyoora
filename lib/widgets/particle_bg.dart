// lib/widgets/particle_bg.dart
import 'dart:math';
import 'package:flutter/material.dart';

class ParticleBg extends StatefulWidget {
  final Widget child;
  const ParticleBg({super.key, required this.child});

  @override
  State<ParticleBg> createState() => _ParticleBgState();
}

class _ParticleBgState extends State<ParticleBg>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final List<_Particle> _particles = [];
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 28; i++) {
      _particles.add(_Particle(_rng));
    }
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            for (final p in _particles) {
              p.update();
            }
            return CustomPaint(
              painter: _ParticlePainter(_particles),
              child: const SizedBox.expand(),
            );
          },
        ),
        widget.child,
      ],
    );
  }
}

class _Particle {
  final Random _rng;
  late double x, y, vx, vy, radius, opacity;
  late Color color;

  static const _colors = [
    Color(0xFFD4AF37),
    Color(0xFF9B59D4),
    Color(0xFFFFFFFF),
  ];

  _Particle(this._rng) {
    _reset(initial: true);
  }

  void _reset({bool initial = false}) {
    x = _rng.nextDouble();
    y = initial ? _rng.nextDouble() : 1.1;
    vx = (_rng.nextDouble() - 0.5) * 0.0008;
    vy = -(_rng.nextDouble() * 0.0006 + 0.0002);
    radius = _rng.nextDouble() * 1.8 + 0.6;
    opacity = _rng.nextDouble() * 0.4 + 0.1;
    color = _colors[_rng.nextInt(_colors.length)];
  }

  void update() {
    x += vx;
    y += vy;
    if (y < -0.05 || x < -0.05 || x > 1.05) _reset();
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  _ParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withOpacity(p.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}
