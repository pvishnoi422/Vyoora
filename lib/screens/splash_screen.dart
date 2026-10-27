// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/storage_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _letters = ['V', 'Y', 'O', 'O', 'R', 'A'];
  final List<AnimationController> _letterCtrls = [];
  final List<Animation<double>>   _letterFades = [];
  late AnimationController _glowCtrl;
  late Animation<double>   _glow;
  late AnimationController _fadeOutCtrl;
  late Animation<double>   _fadeOut;

  @override
  void initState() {
    super.initState();

    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _glow = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut);

    _fadeOutCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeOut = CurvedAnimation(parent: _fadeOutCtrl, curve: Curves.easeIn);

    for (int i = 0; i < _letters.length; i++) {
      final ctrl = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 380));
      _letterCtrls.add(ctrl);
      _letterFades.add(CurvedAnimation(parent: ctrl, curve: Curves.easeOut));
    }

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 500));

    // Reveal letters one by one
    for (int i = 0; i < _letters.length; i++) {
      await Future.delayed(const Duration(milliseconds: 160));
      if (mounted) _letterCtrls[i].forward();
    }

    // Hold then glow
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) _glowCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 900));

    // Fade entire screen to black
    if (mounted) await _fadeOutCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;
    final showOnboarding = await StorageService.shouldShowOnboarding();
    if (!mounted) return;
    Navigator.pushReplacementNamed(
        context, showOnboarding ? '/onboarding' : '/home');
  }

  @override
  void dispose() {
    for (final c in _letterCtrls) c.dispose();
    _glowCtrl.dispose();
    _fadeOutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _fadeOut,
        builder: (_, child) {
          return Stack(
            children: [
              // Content
              Opacity(opacity: 1 - _fadeOut.value, child: child),
              // Black overlay fading in
              if (_fadeOut.value > 0)
                Opacity(
                  opacity: _fadeOut.value,
                  child: Container(color: Colors.black),
                ),
            ],
          );
        },
        child: Center(
          child: AnimatedBuilder(
            animation: _glow,
            builder: (_, __) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_letters.length, (i) {
                  return FadeTransition(
                    opacity: _letterFades[i],
                    child: Text(
                      _letters[i],
                      style: GoogleFonts.cormorantGaramond(
                        fontSize: 52,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 12,
                        color: const Color(0xFFD4AF37)
                            .withOpacity(0.85 + 0.15 * _glow.value),
                        shadows: [
                          Shadow(
                            color: const Color(0xFFD4AF37)
                                .withOpacity(0.5 * _glow.value),
                            blurRadius: 32,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ),
    );
  }
}
