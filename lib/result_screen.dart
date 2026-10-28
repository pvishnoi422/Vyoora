// lib/result_screen.dart
import 'dart:math';
import 'models/analysis_outcome.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'components/vyoora_scaffold.dart';

class ResultScreen extends StatefulWidget {
  final Map<String, dynamic> result;
  const ResultScreen({super.key, required this.result});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  late AnimationController _scoreCtrl;
  late AnimationController _meterCtrl;
  late AnimationController _cardsCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _scoreAnim;
  late Animation<double> _meterAnim;
  late Animation<double> _cardsAnim;
  late Animation<double> _fadeAnim;
  bool _scoreExpanded = false;
  bool _allIngredientsExpanded = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scoreCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _meterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _cardsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _scoreAnim = CurvedAnimation(
      parent: _scoreCtrl,
      curve: Curves.easeOutCubic,
    );
    _meterAnim = CurvedAnimation(
      parent: _meterCtrl,
      curve: Curves.easeOutCubic,
    );
    _cardsAnim = CurvedAnimation(
      parent: _cardsCtrl,
      curve: Curves.easeOutCubic,
    );

    _fadeCtrl.forward();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _scoreCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _meterCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _cardsCtrl.forward();
    });
  }

  @override
  void dispose() {
    _scoreCtrl.dispose();
    _meterCtrl.dispose();
    _cardsCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Color _scoreColor(int score) {
    if (score >= 80) return const Color(0xFF4CAF50);
    if (score >= 60) return const Color(0xFFD4AF37);
    return const Color(0xFFE07070);
  }

  bool _containsKeyword(Map c, List<String> kws) {
    final t = '${c['ingredient'] ?? ''} ${c['reason'] ?? ''}'.toLowerCase();
    return kws.any((k) => t.contains(k));
  }

  @override
  Widget build(BuildContext context) {
    final outcome = AnalysisOutcome.fromJson(widget.result);
    if (!outcome.isSuccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('Analysis unavailable')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, size: 40),
                const SizedBox(height: 16),
                Text(outcome.message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text('Go back and retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final summary = (widget.result['summary'] as String? ?? '');
    final count = (widget.result['ingredient_count'] as int? ?? 0);
    final scoreLabel = (widget.result['score_label'] as String? ?? '');
    final productType = (widget.result['product_type'] as String? ?? '');
    final productDetail =
        (widget.result['product_type_detail'] as String? ?? '');
    final formulaType = (widget.result['formula_type'] as String? ?? '');
    final brand = (widget.result['brand'] as String? ?? '');
    final productName = (widget.result['product_name'] as String? ?? '');
    final skinCompat =
        widget.result['skin_compatibility'] as Map<String, dynamic>?;
    final whoAvoid =
        ((widget.result['who_should_avoid'] as List<dynamic>?) ?? [])
            .map((e) => e.toString())
            .toList();
    final scoreRat = widget.result['score_rationale'] as Map<String, dynamic>?;
    final concerns = ((widget.result['concerns'] as List<dynamic>?) ?? [])
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final allIngredients =
        ((widget.result['all_ingredients'] as List<dynamic>?) ?? [])
            .map((e) => e.toString())
            .toList();
    final confidence = (widget.result['confidence'] as String? ?? '');
    final score =
        (widget.result['smart_score'] as int?) ??
        (100 -
            ((concerns.length / count.clamp(1, 80)) * 100)
                .clamp(0, 60)
                .round());
    final scoreColor = _scoreColor(score);

    final hasEuBanned = concerns.any((c) => c['eu_banned'] == true);
    final hasEuRestricted = concerns.any((c) => c['eu_restricted'] == true);

    // Unique sources
    final allSources = <Map<String, dynamic>>[];
    final seenSrc = <String>{};
    for (final c in concerns) {
      for (final l in ((c['links'] as List<dynamic>?) ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      )) {
        final src = (l['source'] ?? '').toString();
        if (src.isNotEmpty && !seenSrc.contains(src)) {
          seenSrc.add(src);
          allSources.add(l);
        }
      }
    }

    final irritation =
        concerns.any(
          (c) => _containsKeyword(c, ['irritat', 'sensitiv', 'fragrance']),
        )
        ? 0.75
        : (concerns.length / 10.0).clamp(0.0, 1.0);
    final acne =
        concerns.any((c) => _containsKeyword(c, ['comedogen', 'acne', 'pore']))
        ? 0.6
        : 0.15;
    final fungal =
        concerns.any(
          (c) => _containsKeyword(c, ['fungal', 'malassezia', 'ester']),
        )
        ? 0.55
        : 0.2;

    return VyooraScaffold(
      title: 'Analysis',
      showParticles: false,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
          children: [
            // ── Brand / product name ──
            if (brand.isNotEmpty || productName.isNotEmpty) ...[
              if (brand.isNotEmpty)
                Center(
                  child: Text(
                    brand,
                    style: GoogleFonts.cookie(
                      color: const Color(0xFFD4AF37),
                      fontSize: 32,
                    ),
                  ),
                ),
              if (productName.isNotEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      productName,
                      style: GoogleFonts.cinzel(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                        letterSpacing: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              if (productType.isNotEmpty && productType != 'Unknown')
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      productDetail.isNotEmpty ? productDetail : productType,
                      style: GoogleFonts.cinzel(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 11,
                        letterSpacing: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],

            // ── Decorative header ──
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1,
                    color: const Color(0xFFD4AF37).withOpacity(0.2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '✦',
                    style: TextStyle(
                      color: const Color(0xFFD4AF37).withOpacity(0.5),
                      fontSize: 14,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1,
                    color: const Color(0xFFD4AF37).withOpacity(0.2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Product type pill ──
            if (productType.isNotEmpty && productType != 'Unknown')
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9B59D4).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF9B59D4).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.category_outlined,
                              size: 12,
                              color: Color(0xFF9B59D4),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              productDetail.isNotEmpty
                                  ? productDetail
                                  : productType,
                              style: const TextStyle(
                                color: Color(0xFF9B59D4),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (formulaType.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4AF37).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFD4AF37).withOpacity(0.2),
                            ),
                          ),
                          child: Text(
                            formulaType,
                            style: const TextStyle(
                              color: Color(0xFFD4AF37),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // ── EU warning banner ──
            if (hasEuBanned || hasEuRestricted)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: hasEuBanned
                      ? const Color(0xFFE07070).withOpacity(0.08)
                      : const Color(0xFFD4AF37).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasEuBanned
                        ? const Color(0xFFE07070).withOpacity(0.3)
                        : const Color(0xFFD4AF37).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasEuBanned ? Icons.gavel : Icons.info_outline,
                      size: 16,
                      color: hasEuBanned
                          ? const Color(0xFFE07070)
                          : const Color(0xFFD4AF37),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        hasEuBanned
                            ? 'Contains ingredient(s) banned in EU cosmetics'
                            : 'Contains EU-restricted fragrance allergen(s)',
                        style: GoogleFonts.cinzel(
                          color: hasEuBanned
                              ? const Color(0xFFE07070)
                              : const Color(0xFFD4AF37),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Score card ──
            AnimatedBuilder(
              animation: _scoreAnim,
              builder: (_, __) => Transform.translate(
                offset: Offset(0, 18 * (1 - _scoreAnim.value)),
                child: Opacity(
                  opacity: _scoreAnim.value.clamp(0.0, 1.0),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0A0A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: scoreColor.withOpacity(0.25)),
                      boxShadow: [
                        BoxShadow(
                          color: scoreColor.withOpacity(0.1),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 96,
                                  height: 96,
                                  child: CustomPaint(
                                    painter: _ScoreRingPainter(
                                      score: score,
                                      progress: _scoreAnim.value,
                                      color: scoreColor,
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${(score * _scoreAnim.value).round()}',
                                            style: GoogleFonts.cookie(
                                              color: scoreColor,
                                              fontSize: 30,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            '/100',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.3,
                                              ),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Formula Safety Score',
                                  style: GoogleFonts.cinzel(
                                    color: Colors.white.withOpacity(0.35),
                                    fontSize: 9,
                                    letterSpacing: 0.8,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    scoreLabel.isNotEmpty
                                        ? scoreLabel
                                        : _defaultLabel(score),
                                    style: GoogleFonts.cookie(
                                      color: scoreColor,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _buildMicrocopy(score),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.82),
                                      fontSize: 14,
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  _RiskMeter(
                                    label: 'Irritation',
                                    value: irritation.clamp(0.0, 1.0),
                                    animation: _meterAnim,
                                  ),
                                  const SizedBox(height: 8),
                                  _RiskMeter(
                                    label: 'Acne risk',
                                    value: acne.clamp(0.0, 1.0),
                                    animation: _meterAnim,
                                  ),
                                  const SizedBox(height: 8),
                                  _RiskMeter(
                                    label: 'Fungal acne',
                                    value: fungal.clamp(0.0, 1.0),
                                    animation: _meterAnim,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Why this score - always visible top 3
                        if (scoreRat != null) ...[
                          const SizedBox(height: 14),
                          _ScoreRationaleInline(rationale: scoreRat),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => setState(
                              () => _scoreExpanded = !_scoreExpanded,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _scoreExpanded
                                      ? 'Show less'
                                      : 'Full breakdown',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.35),
                                    fontSize: 13,
                                  ),
                                ),
                                Icon(
                                  _scoreExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: Colors.white.withOpacity(0.3),
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                          if (_scoreExpanded) ...[
                            const SizedBox(height: 10),
                            _ScoreRationale(rationale: scoreRat),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // ── Summary ──
            AnimatedBuilder(
              animation: _meterAnim,
              builder: (_, child) => Opacity(
                opacity: _meterAnim.value.clamp(0.0, 1.0),
                child: child,
              ),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1E1E1E)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (count > 0)
                          _Badge('$count ingredients', const Color(0xFFD4AF37)),
                        if (count > 0 && concerns.isNotEmpty)
                          const SizedBox(width: 8),
                        if (concerns.isNotEmpty)
                          _Badge(
                            '${concerns.length} concern${concerns.length == 1 ? '' : 's'}',
                            const Color(0xFFE07070),
                          ),
                        if (confidence.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _Badge(
                            '$confidence confidence',
                            const Color(0xFF9B59D4),
                          ),
                        ],
                      ],
                    ),
                    if (count > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 12,
                            color: Color(0xFF4CAF50),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$count ingredients detected · $count analyzed',
                            style: GoogleFonts.cinzel(
                              color: Colors.white.withOpacity(0.35),
                              fontSize: 11,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      summary,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 16,
                        height: 1.7,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            // ── Skin profile compatibility ──
            if (skinCompat != null &&
                (skinCompat['best_for'] as List? ?? []).isNotEmpty) ...[
              AnimatedBuilder(
                animation: _meterAnim,
                builder: (_, child) => Opacity(
                  opacity: _meterAnim.value.clamp(0.0, 1.0),
                  child: child!,
                ),
                child: _SkinCompatCard(compat: skinCompat),
              ),
              const SizedBox(height: 18),
            ],

            // ── Who should avoid ──
            if (whoAvoid.isNotEmpty) ...[
              AnimatedBuilder(
                animation: _meterAnim,
                builder: (_, child) => Opacity(
                  opacity: _meterAnim.value.clamp(0.0, 1.0),
                  child: child!,
                ),
                child: _WhoShouldAvoidCard(items: whoAvoid),
              ),
              const SizedBox(height: 22),
            ],

            // ── Ingredients to know ──
            if (concerns.isEmpty)
              AnimatedBuilder(
                animation: _cardsAnim,
                builder: (_, child) => Opacity(
                  opacity: _cardsAnim.value.clamp(0.0, 1.0),
                  child: child,
                ),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF071207),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF4CAF50).withOpacity(0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            color: Color(0xFF4CAF50),
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No concerns were flagged in the ingredients read. This does not establish product safety.',
                              style: GoogleFonts.cookie(
                                color: const Color(0xFF4CAF50),
                                fontSize: 19,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => launchUrl(
                          Uri.parse(
                            'https://ec.europa.eu/growth/sectors/cosmetics/cosing_en',
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.open_in_new,
                              size: 12,
                              color: Color(0xFFD4AF37),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Based on EU CosIng database & peer-reviewed dermatology research',
                                style: TextStyle(
                                  color: const Color(
                                    0xFFD4AF37,
                                  ).withOpacity(0.7),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    color: const Color(0xFFD4AF37).withOpacity(0.6),
                    margin: const EdgeInsets.only(right: 10),
                  ),
                  Text(
                    'INGREDIENTS TO KNOW',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 13,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...concerns.asMap().entries.map((entry) {
                final i = entry.key;
                return AnimatedBuilder(
                  animation: _cardsAnim,
                  builder: (_, child) {
                    final delay = (i * 0.15).clamp(0.0, 0.6);
                    final local = ((_cardsAnim.value - delay) / (1 - delay))
                        .clamp(0.0, 1.0);
                    return Transform.translate(
                      offset: Offset(0, 22 * (1 - local)),
                      child: Opacity(
                        opacity: local.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: _ConcernCard(concern: entry.value),
                );
              }),
            ],

            // ── All Ingredients dropdown ──
            if (allIngredients.isNotEmpty) ...[
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => setState(
                  () => _allIngredientsExpanded = !_allIngredientsExpanded,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF252525)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.list_alt_outlined,
                            size: 15,
                            color: Color(0xFFD4AF37),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'All Ingredients (${allIngredients.length})',
                            style: GoogleFonts.cinzel(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      Icon(
                        _allIngredientsExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.white.withOpacity(0.3),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              if (_allIngredientsExpanded) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E1E1E)),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: allIngredients.map((ing) {
                      final isConcern = concerns.any(
                        (c) =>
                            (c['ingredient'] as String? ?? '').toLowerCase() ==
                            ing.toLowerCase(),
                      );
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isConcern
                              ? const Color(0xFFE07070).withOpacity(0.08)
                              : const Color(0xFF151515),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isConcern
                                ? const Color(0xFFE07070).withOpacity(0.3)
                                : const Color(0xFF252525),
                          ),
                        ),
                        child: Text(
                          ing,
                          style: GoogleFonts.cinzel(
                            color: isConcern
                                ? const Color(0xFFE07070)
                                : Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],

            // ── Sources ──
            if (allSources.isNotEmpty) ...[
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 1,
                      color: const Color(0xFFD4AF37).withOpacity(0.1),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'SOURCES',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 12,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: const Color(0xFFD4AF37).withOpacity(0.1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: allSources.map((l) {
                  final src = (l['source'] ?? '').toString();
                  final url = (l['url'] ?? '').toString();
                  return GestureDetector(
                    onTap: url.isEmpty
                        ? null
                        : () => launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFD4AF37).withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.open_in_new,
                            size: 10,
                            color: Color(0xFFD4AF37),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            src,
                            style: const TextStyle(
                              color: Color(0xFFD4AF37),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Text(
                'Evidence sourced from dermatology literature and cosmetic safety databases. Individual reactions vary.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ],

            // ── Disclaimer footer ──
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E1E1E)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Color(0xFF444444),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI-generated analysis for informational purposes only. Not medical or dermatological advice. Always patch test new products and consult a dermatologist for personalised guidance.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _defaultLabel(int score) {
    if (score >= 85) return 'Sensitive-skin friendly';
    if (score >= 75) return 'Balanced for most skin types';
    if (score >= 60) return 'Use with awareness';
    return 'High sensitization potential';
  }

  String _buildMicrocopy(int score) {
    if (score >= 80) return 'A well-tolerated formula for most skin types.';
    if (score >= 60)
      return 'Some ingredients may cause sensitivity in certain individuals.';
    return 'Multiple ingredients with sensitization potential detected.';
  }
}

// ── Score rationale inline (top 3 always visible) ────────────────────────────
class _ScoreRationaleInline extends StatelessWidget {
  final Map<String, dynamic> rationale;
  const _ScoreRationaleInline({required this.rationale});

  @override
  Widget build(BuildContext context) {
    final positives = (rationale['positives'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final negatives = (rationale['negatives'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final items = <Map<String, dynamic>>[];
    for (final p in positives.take(2)) items.add({'text': p, 'positive': true});
    for (final n in negatives.take(1))
      items.add({'text': n, 'positive': false});

    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    item['positive'] ? Icons.check : Icons.close,
                    size: 13,
                    color: item['positive']
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFE07070),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item['text'],
                      style: GoogleFonts.cinzel(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

// ── Score rationale ───────────────────────────────────────────────────────────
class _ScoreRationale extends StatelessWidget {
  final Map<String, dynamic> rationale;
  const _ScoreRationale({required this.rationale});

  @override
  Widget build(BuildContext context) {
    final positives = (rationale['positives'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final negatives = (rationale['negatives'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final confidence =
        (rationale['evidence_confidence'] as String? ?? 'Moderate');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF252525)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...positives.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.add, size: 13, color: Color(0xFF4CAF50)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...negatives.map(
            (n) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.remove, size: 13, color: Color(0xFFE07070)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      n,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.science_outlined,
                size: 13,
                color: Color(0xFF9B59D4),
              ),
              const SizedBox(width: 8),
              Text(
                'Evidence confidence: $confidence',
                style: const TextStyle(color: Color(0xFF9B59D4), fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Skin compat card ──────────────────────────────────────────────────────────
class _SkinCompatCard extends StatelessWidget {
  final Map<String, dynamic> compat;
  const _SkinCompatCard({required this.compat});

  @override
  Widget build(BuildContext context) {
    final bestFor = (compat['best_for'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final caution = (compat['use_caution'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final lessIdeal = (compat['less_ideal_for'] as List? ?? [])
        .map((e) => e.toString())
        .toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                color: const Color(0xFF9B59D4).withOpacity(0.7),
                margin: const EdgeInsets.only(right: 10),
              ),
              Text(
                'SKIN PROFILE COMPATIBILITY',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 13,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (bestFor.isNotEmpty)
            _CompatRow(
              label: 'Best for',
              items: bestFor,
              color: const Color(0xFF4CAF50),
            ),
          if (caution.isNotEmpty)
            _CompatRow(
              label: 'Use caution',
              items: caution,
              color: const Color(0xFFD4AF37),
            ),
          if (lessIdeal.isNotEmpty)
            _CompatRow(
              label: 'Less ideal for',
              items: lessIdeal,
              color: const Color(0xFFE07070),
            ),
        ],
      ),
    );
  }
}

class _CompatRow extends StatelessWidget {
  final String label;
  final List<String> items;
  final Color color;
  const _CompatRow({
    required this.label,
    required this.items,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: items
                  .map(
                    (s) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withOpacity(0.25)),
                      ),
                      child: Text(
                        s.toLowerCase(),
                        style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Who should avoid ─────────────────────────────────────────────────────────
class _WhoShouldAvoidCard extends StatelessWidget {
  final List<String> items;
  const _WhoShouldAvoidCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE07070).withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                color: const Color(0xFFE07070).withOpacity(0.7),
                margin: const EdgeInsets.only(right: 10),
              ),
              Text(
                'WHO SHOULD USE CAUTION',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 13,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items
                .map(
                  (s) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE07070).withOpacity(0.07),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFE07070).withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 15,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ── Score ring ────────────────────────────────────────────────────────────────
class _ScoreRingPainter extends CustomPainter {
  final int score;
  final double progress;
  final Color color;
  _ScoreRingPainter({
    required this.score,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2, r = min(cx, cy) - 7;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    canvas.drawArc(
      rect,
      -pi / 2,
      2 * pi,
      false,
      Paint()
        ..color = Colors.white.withOpacity(0.06)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke,
    );
    canvas.drawArc(
      rect,
      -pi / 2,
      (score / 100) * 2 * pi * progress,
      false,
      Paint()
        ..color = color
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * progress),
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter o) => o.progress != progress;
}

// ── Risk meter ────────────────────────────────────────────────────────────────
class _RiskMeter extends StatelessWidget {
  final String label;
  final double value;
  final Animation<double> animation;
  const _RiskMeter({
    required this.label,
    required this.value,
    required this.animation,
  });

  Color get _color => value < 0.35
      ? const Color(0xFF4CAF50)
      : value < 0.65
      ? const Color(0xFFD4AF37)
      : const Color(0xFFE07070);
  String get _lbl => value < 0.35
      ? 'Low'
      : value < 0.65
      ? 'Moderate'
      : 'High';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
            Text(
              _lbl,
              style: TextStyle(
                color: _color,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AnimatedBuilder(
          animation: animation,
          builder: (_, __) => ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value * animation.value,
              minHeight: 4,
              backgroundColor: Colors.white.withOpacity(0.06),
              valueColor: AlwaysStoppedAnimation<Color>(_color),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Badge ─────────────────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ── Concern card ──────────────────────────────────────────────────────────────
class _ConcernCard extends StatelessWidget {
  final Map<String, dynamic> concern;
  const _ConcernCard({required this.concern});

  @override
  Widget build(BuildContext context) {
    final ingredient = (concern['ingredient'] ?? '').toString();
    final reason = (concern['reason'] ?? '').toString();
    final category = (concern['category'] ?? '').toString();
    final position = (concern['ingredient_position'] as int?) ?? 99;
    final euBanned = concern['eu_banned'] == true;
    final euRestr = concern['eu_restricted'] == true;
    final euNote = (concern['eu_note'] ?? '').toString();
    final isHighConc = position <= 5;
    final isAvoid =
        euBanned ||
        reason.toLowerCase().contains('avoid') ||
        ingredient.toLowerCase().contains('fragrance');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: euBanned
              ? const Color(0xFFE07070).withOpacity(0.35)
              : isAvoid
              ? const Color(0xFFE07070).withOpacity(0.2)
              : const Color(0xFFD4AF37).withOpacity(0.15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ingredient.isEmpty ? 'Unknown ingredient' : ingredient,
                        style: GoogleFonts.cookie(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (position < 99)
                        Text(
                          '#$position in formula',
                          style: GoogleFonts.cinzel(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                    ],
                  ),
                ),
                // Chips row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isHighConc)
                      _SmallChip('High conc.', const Color(0xFF9B59D4)),
                    if (isHighConc) const SizedBox(width: 4),
                    if (category.isNotEmpty)
                      _SmallChip(category, const Color(0xFF9B59D4)),
                    if (category.isNotEmpty) const SizedBox(width: 4),
                    _SmallChip(
                      isAvoid ? 'Avoid' : 'Caution',
                      isAvoid
                          ? const Color(0xFFE07070)
                          : const Color(0xFFD4AF37),
                    ),
                  ],
                ),
              ],
            ),

            // EU badge
            if (euBanned || euRestr) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: euBanned
                      ? const Color(0xFFE07070).withOpacity(0.1)
                      : const Color(0xFFD4AF37).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: euBanned
                        ? const Color(0xFFE07070).withOpacity(0.3)
                        : const Color(0xFFD4AF37).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      euBanned ? Icons.gavel : Icons.info_outline,
                      size: 12,
                      color: euBanned
                          ? const Color(0xFFE07070)
                          : const Color(0xFFD4AF37),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        euNote.isNotEmpty
                            ? euNote
                            : euBanned
                            ? 'Banned in EU cosmetics'
                            : 'EU-restricted fragrance allergen',
                        style: GoogleFonts.cinzel(
                          color: euBanned
                              ? const Color(0xFFE07070)
                              : const Color(0xFFD4AF37),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),
            Text(
              reason,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 16,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  final String label;
  final Color color;
  const _SmallChip(this.label, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
