// lib/widgets/lumi_orb.dart
import 'dart:math';
import 'package:flutter/material.dart';

class LumiOrb extends StatefulWidget {
  final bool scanning;
  const LumiOrb({super.key, this.scanning = false});

  @override
  State<LumiOrb> createState() => _LumiOrbState();
}

class _LumiOrbState extends State<LumiOrb> with TickerProviderStateMixin {
  late AnimationController _breathCtrl;
  late AnimationController _haloCtrl;
  late AnimationController _scanCtrl;
  late AnimationController _rainCtrl;
  late Animation<double>   _breath;
  late Animation<double>   _scanPulse;
  bool _raining = false;
  final List<_GoldParticle> _particles = [];
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _breathCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4500),
    )..repeat(reverse: true);
    _breath = CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut);

    _haloCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 12),
    )..repeat();

    _scanCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800),
    );
    _scanPulse = CurvedAnimation(parent: _scanCtrl, curve: Curves.easeOut);

    _rainCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800),
    );
    _rainCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() { _raining = false; _particles.clear(); });
      }
    });
    _rainCtrl.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void didUpdateWidget(LumiOrb old) {
    super.didUpdateWidget(old);
    if (widget.scanning && !old.scanning) {
      _scanCtrl.repeat(reverse: true);
    } else if (!widget.scanning && old.scanning) {
      _scanCtrl.stop(); _scanCtrl.value = 0;
    }
  }

  void _triggerRain() {
    if (_raining) return;
    setState(() {
      _raining = true;
      _particles.clear();
      for (int i = 0; i < 30; i++) {
        _particles.add(_GoldParticle(
          x: _rng.nextDouble() * 300 - 75,
          delay: _rng.nextDouble() * 0.4,
          speed: 0.5 + _rng.nextDouble() * 0.5,
          size: 3 + _rng.nextDouble() * 5,
          drift: (_rng.nextDouble() - 0.5) * 60,
        ));
      }
    });
    _rainCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    _breathCtrl.dispose(); _haloCtrl.dispose();
    _scanCtrl.dispose(); _rainCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _triggerRain,
      child: AnimatedBuilder(
        animation: Listenable.merge([_breath, _haloCtrl, _scanPulse]),
        builder: (_, __) {
          final breathVal   = _breath.value;
          final scanVal     = _scanPulse.value;
          final haloAngle   = _haloCtrl.value * 2 * pi;
          final glowOpacity = 0.15 + breathVal * 0.1 + scanVal * 0.15;
          final glowRadius  = 20.0 + breathVal * 12 + scanVal * 16;
          final scale       = 1.0 + breathVal * 0.03 + scanVal * 0.05;

          return SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Gold rain particles
                if (_raining)
                  ...(_particles.map((p) {
                    final t = (_rainCtrl.value - p.delay).clamp(0.0, 1.0);
                    final progress = (t / p.speed).clamp(0.0, 1.0);
                    final opacity = progress < 0.2
                        ? progress / 0.2
                        : progress > 0.7
                            ? 1.0 - (progress - 0.7) / 0.3
                            : 1.0;
                    return Positioned(
                      left: 100 + p.x + p.drift * progress,
                      top: 50 + progress * 140,
                      child: Opacity(
                        opacity: opacity.clamp(0.0, 1.0),
                        child: Container(
                          width: p.size,
                          height: p.size,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFD4AF37),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFD4AF37).withOpacity(0.6),
                                blurRadius: p.size,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  })),

                // Ambient glow
                Container(
                  width: 150, height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD4AF37).withOpacity(glowOpacity),
                        blurRadius: glowRadius * 2,
                      ),
                    ],
                  ),
                ),

                // Rotating halo ring
                Transform.rotate(
                  angle: haloAngle,
                  child: Container(
                    width: 130, height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFD4AF37).withOpacity(0.1 + breathVal * 0.05),
                        width: 1.0,
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFD4AF37).withOpacity(0.5 + breathVal * 0.3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFD4AF37).withOpacity(0.5),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Lumi image
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD4AF37).withOpacity(glowOpacity * 1.5),
                          blurRadius: glowRadius,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/lumi_orb.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GoldParticle {
  final double x, delay, speed, size, drift;
  const _GoldParticle({
    required this.x, required this.delay,
    required this.speed, required this.size, required this.drift,
  });
}
