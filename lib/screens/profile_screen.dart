// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/particle_bg.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080808),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text('PROFILE',
          style: GoogleFonts.cinzel(
            color: const Color(0xFFD4AF37), fontSize: 16,
            fontWeight: FontWeight.w600, letterSpacing: 3)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFD4AF37).withOpacity(0.1))),
      ),
      body: ParticleBg(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 32),

              // Avatar
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF111111),
                  border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3), width: 1.5),
                ),
                child: const Icon(Icons.person_outline, size: 40, color: Color(0xFFD4AF37)),
              ),
              const SizedBox(height: 20),

              Text('Your Skin Profile',
                style: GoogleFonts.cookie(
                  color: Colors.white, fontSize: 26,
                  fontWeight: FontWeight.w600, fontStyle: FontStyle.italic)),
              const SizedBox(height: 8),
              Text(
                'Vyoora uses EU CosIng, CIR, PubMed and IFRA databases to analyze your skincare ingredients.',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15, height: 1.6),
                textAlign: TextAlign.center),

              const SizedBox(height: 32),

              // Legal & info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1A1A1A))),
                child: Column(children: [
                  _InfoRow(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy',
                    onTap: () => launchUrl(
                      Uri.parse('https://vyoora.notion.site/privacy'),
                      mode: LaunchMode.externalApplication),
                  ),
                  _Divider(),
                  _InfoRow(
                    icon: Icons.description_outlined,
                    label: 'Terms of Use',
                    onTap: () => launchUrl(
                      Uri.parse('https://vyoora.notion.site/terms'),
                      mode: LaunchMode.externalApplication),
                  ),
                  _Divider(),
                  _InfoRow(
                    icon: Icons.science_outlined,
                    label: 'Data Sources',
                    trailing: 'EU CosIng, CIR, PubMed, IFRA',
                    onTap: null,
                  ),
                  _Divider(),
                  _InfoRow(
                    icon: Icons.info_outline,
                    label: 'Version',
                    trailing: '1.0.0',
                    onTap: null,
                  ),
                ]),
              ),

              const SizedBox(height: 16),

              Text(
                'Vyoora provides AI-generated ingredient analysis for informational purposes only. This is not medical or dermatological advice.',
                style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 14, height: 1.6),
                textAlign: TextAlign.center),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon; final String text;
  const _Feature(this.icon, this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(icon, size: 16, color: const Color(0xFFD4AF37).withOpacity(0.5)),
        const SizedBox(width: 12),
        Text(text, style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 16)),
      ]));
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String?  trailing;
  final VoidCallback? onTap;
  const _InfoRow({required this.icon, required this.label, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(children: [
          Icon(icon, size: 16, color: Colors.white.withOpacity(0.3)),
          const SizedBox(width: 12),
          Expanded(child: Text(label,
            style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 16))),
          if (trailing != null)
            Text(trailing!, style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 14))
          else if (onTap != null)
            Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white.withOpacity(0.2)),
        ]),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: const Color(0xFF1A1A1A));
}
