// lib/components/vyoora_scaffold.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/particle_bg.dart';

class VyooraScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final bool showParticles;

  const VyooraScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.showParticles = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = SafeArea(child: body);
    if (showParticles) content = ParticleBg(child: content);

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080808),
        elevation: 0,
        centerTitle: true,
        title: Text(
          title.toUpperCase(),
          style: GoogleFonts.cinzel(
            color: const Color(0xFFD4AF37),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 4,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFD4AF37)),
        actions: actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              height: 1,
              color: const Color(0xFFD4AF37).withOpacity(0.1)),
        ),
      ),
      body: content,
    );
  }
}
