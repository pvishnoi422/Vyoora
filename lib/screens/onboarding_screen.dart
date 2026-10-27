// lib/screens/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/storage_service.dart';
import '../widgets/particle_bg.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  late AnimationController _fadeCtrl;
  late Animation<double> _fade;
  int _page = 0;
  bool _dontShowAgain = false;

  static const _pages = [
    _PageData(
      icon: Icons.document_scanner_outlined,
      title: 'Know What\'s Really In Your Skincare',
      subtitle:
          'Point your camera at any skincare label and instantly see what you\'re putting on your skin.',
    ),
    _PageData(
      icon: Icons.science_outlined,
      title: 'Avoid Ingredients That Don\'t Work For You',
      subtitle:
          'Every flagged ingredient is backed by peer-reviewed research. Not opinions. Evidence.',
    ),
    _PageData(
      icon: Icons.auto_awesome,
      title: 'Get Instant Answers From Your Personal Skin Advisor',
      subtitle:
          'Ask anything about your routine, your skin type, or specific ingredients.',
    ),
    _PageData(
      icon: Icons.gavel_outlined,
      title: 'A note before you start',
      subtitle: '',
      isLegal: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page < _pages.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      if (_dontShowAgain) {
        await StorageService.setSkipOnboarding(true);
      }
      if (mounted) Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: ParticleBg(
        child: FadeTransition(
          opacity: _fade,
          child: SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'VYOORA',
                        style: GoogleFonts.cinzel(
                          color: const Color(0xFFD4AF37),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 4,
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (_dontShowAgain) {
                            await StorageService.setSkipOnboarding(true);
                          }
                          if (mounted) {
                            Navigator.pushReplacementNamed(context, '/home');
                          }
                        },
                        child: Text(
                          'Skip',
                          style: GoogleFonts.cinzel(
                            color: Colors.white.withOpacity(0.82),
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Decorative line
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          color: const Color(0xFFD4AF37).withOpacity(0.15),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '✦',
                          style: GoogleFonts.cinzel(
                            color: const Color(0xFFD4AF37).withOpacity(0.4),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: const Color(0xFFD4AF37).withOpacity(0.15),
                        ),
                      ),
                    ],
                  ),
                ),

                // Pages
                Expanded(
                  child: PageView.builder(
                    controller: _pageCtrl,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => _pages[i].isLegal
                        ? _LegalPage()
                        : _OnboardPage(data: _pages[i]),
                  ),
                ),

                // Don't show again (last page only)
                if (isLast)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _dontShowAgain = !_dontShowAgain),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: _dontShowAgain
                                  ? const Color(0xFFD4AF37)
                                  : Colors.transparent,
                              border: Border.all(
                                color: const Color(0xFFD4AF37).withOpacity(0.6),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: _dontShowAgain
                                ? const Icon(
                                    Icons.check,
                                    size: 14,
                                    color: Color(0xFF080808),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "Don't show this again",
                            style: GoogleFonts.cinzel(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 24 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: i == _page
                            ? const Color(0xFFD4AF37)
                            : const Color(0xFF2A2A2A),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // CTA
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: GestureDetector(
                    onTap: _next,
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD4AF37).withOpacity(0.28),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          isLast ? 'Scan Your First Product' : 'Next',
                          style: GoogleFonts.cookie(
                            color: const Color(0xFF080808),
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Legal page ───────────────────────────────────────────────────────────────
class _LegalPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E0E),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFFD4AF37).withOpacity(0.3),
              ),
            ),
            child: const Icon(
              Icons.gavel_outlined,
              size: 30,
              color: Color(0xFFD4AF37),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '✦  Trusted by skincare enthusiasts and ingredient-conscious shoppers  ✦',
            style: TextStyle(
              color: const Color(0xFFD4AF37).withOpacity(0.5),
              fontSize: 12,
              letterSpacing: 0.5,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            'A note before you start',
            style: GoogleFonts.cookie(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFD4AF37).withOpacity(0.15),
              ),
            ),
            child: Text(
              'Data & Privacy\n\n'
              'When you scan a product, the ingredient image is sent to OpenAI\'s API for analysis. No personal information (name, email, or location) is collected or shared. By using Vyoora, you consent to this data being processed by OpenAI in accordance with their privacy policy.\n\n'
              'Vyoora is for informational purposes only.\n\n'
              'Ingredient analysis provided by Vyoora is generated by AI and based on publicly available research. '
              'It is not medical advice, dermatological advice, or a substitute for professional consultation.\n\n'
              'Individual skin reactions vary. An ingredient flagged as a concern may be perfectly safe for your skin, and vice versa. '
              'Always patch test new products and consult a qualified dermatologist before making changes to your skincare routine.\n\n'
              'Vyoora does not diagnose, treat, or prevent any skin condition or disease.',
              style: GoogleFonts.cinzel(
                color: Colors.white.withOpacity(0.8),
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.7,
              ),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Standard onboard page ────────────────────────────────────────────────────
class _OnboardPage extends StatelessWidget {
  final _PageData data;
  const _OnboardPage({required this.data});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withOpacity(0.08),
                  ),
                ),
              ),
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: const Color(0xFF0E0E0E),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withOpacity(0.25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD4AF37).withOpacity(0.1),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  data.icon,
                  size: 44,
                  color: const Color(0xFFD4AF37),
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _dot(0.3),
              const SizedBox(width: 8),
              _dot(0.5),
              const SizedBox(width: 8),
              _dot(0.3),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            data.title,
            style: GoogleFonts.cookie(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            data.subtitle,
            style: GoogleFonts.cinzel(
              color: Colors.white.withOpacity(0.75),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.7,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _dot(double opacity) => Container(
    width: 5,
    height: 5,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFFD4AF37).withOpacity(opacity),
    ),
  );
}

class _PageData {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLegal;
  const _PageData({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isLegal = false,
  });
}
