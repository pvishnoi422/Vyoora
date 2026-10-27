// lib/widgets/scan_zone.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ScanZone extends StatefulWidget {
  const ScanZone({super.key});

  @override
  State<ScanZone> createState() => _ScanZoneState();
}

class _ScanZoneState extends State<ScanZone>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scanAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _scanAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFD4AF37).withOpacity(0.25),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Corner brackets
          ..._corners(),

          // Scan line
          AnimatedBuilder(
            animation: _scanAnim,
            builder: (_, __) {
              final top = 20 + _scanAnim.value * 200;
              return Positioned(
                left: 20,
                right: 20,
                top: top,
                child: Container(
                  height: 1.5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        const Color(0xFFD4AF37).withOpacity(0.8),
                        Colors.transparent,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD4AF37).withOpacity(0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Center content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_a_photo_outlined,
                    size: 40, color: Color(0xFF333333)),
                const SizedBox(height: 12),
                Text(
                  'Tap to scan a label',
                  style: GoogleFonts.cinzel(
                    color: Color(0xFF555555),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Camera or photo library',
                  style:
                      TextStyle(color: Color(0xFF333333), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _corners() {
    const size = 22.0;
    const thickness = 2.0;
    const color = Color(0xFFD4AF37);
    const offset = 14.0;

    return [
      // Top left
      Positioned(
        top: offset,
        left: offset,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: color, width: thickness),
              left: BorderSide(color: color, width: thickness),
            ),
          ),
        ),
      ),
      // Top right
      Positioned(
        top: offset,
        right: offset,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: color, width: thickness),
              right: BorderSide(color: color, width: thickness),
            ),
          ),
        ),
      ),
      // Bottom left
      Positioned(
        bottom: offset,
        left: offset,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: color, width: thickness),
              left: BorderSide(color: color, width: thickness),
            ),
          ),
        ),
      ),
      // Bottom right
      Positioned(
        bottom: offset,
        right: offset,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: color, width: thickness),
              right: BorderSide(color: color, width: thickness),
            ),
          ),
        ),
      ),
    ];
  }
}
