// lib/screens/history_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/storage_service.dart';
import '../result_screen.dart';
import '../widgets/particle_bg.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  List<ScanRecord> _history = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => false; // Always rebuild when tab is switched to

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load(); // Reload every time this screen becomes visible
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    final h = await StorageService.getScanHistory();
    if (mounted)
      setState(() {
        _history = h;
        _loading = false;
      });
  }

  Color _scoreColor(int score) {
    if (score >= 80) return const Color(0xFF4CAF50);
    if (score >= 60) return const Color(0xFFD4AF37);
    return const Color(0xFFE07070);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080808),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          'HISTORY',
          style: GoogleFonts.cinzel(
            color: const Color(0xFFD4AF37),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
          ),
        ),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: Color(0xFF444444),
                size: 20,
              ),
              onPressed: () async {
                await StorageService.clearHistory();
                _load();
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: const Color(0xFFD4AF37).withOpacity(0.1),
          ),
        ),
      ),
      body: ParticleBg(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFD4AF37),
                  strokeWidth: 2,
                ),
              )
            : _history.isEmpty
            ? _EmptyHistory(onRefresh: _load)
            : RefreshIndicator(
                onRefresh: _load,
                color: const Color(0xFFD4AF37),
                backgroundColor: const Color(0xFF111111),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  itemCount: _history.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Only completed analyses appear here. Older scans may need to be analyzed again.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }
                    final r = _history[i - 1];
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, a, __) =>
                              ResultScreen(result: r.fullResult),
                          transitionsBuilder: (_, anim, __, child) =>
                              FadeTransition(opacity: anim, child: child),
                        ),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0F0F),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF1E1E1E)),
                        ),
                        child: Row(
                          children: [
                            // Score ring mini
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _scoreColor(r.score),
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '${r.score}',
                                  style: GoogleFonts.cookie(
                                    color: _scoreColor(r.score),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (r.fullResult['brand'] as String? ?? '')
                                            .isNotEmpty
                                        ? '${r.fullResult['brand']}'
                                        : r.summary.length > 65
                                        ? '${r.summary.substring(0, 65)}…'
                                        : r.summary,
                                    style: GoogleFonts.cookie(
                                      color: const Color(0xFFD4AF37),
                                      fontSize: 20,
                                    ),
                                  ),
                                  if ((r.fullResult['product_type']
                                              as String? ??
                                          '')
                                      .isNotEmpty)
                                    Text(
                                      r.fullResult['product_type'] as String? ??
                                          '',
                                      style: GoogleFonts.cinzel(
                                        color: Colors.white.withOpacity(0.5),
                                        fontSize: 12,
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      _Chip(
                                        '${r.ingredientCount} ingredients',
                                        const Color(0xFFD4AF37),
                                      ),
                                      const SizedBox(width: 6),
                                      _Chip(
                                        '${r.concernCount} concern${r.concernCount == 1 ? '' : 's'}',
                                        const Color(0xFFE07070),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    r.date,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              color: Color(0xFF333333),
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyHistory({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 48, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          Text(
            'No scans yet',
            style: GoogleFonts.cookie(
              color: Colors.white,
              fontSize: 24,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your last 5 completed scans will appear here. Older scans may need to be analyzed again.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onRefresh,
            child: Text(
              'Refresh',
              style: TextStyle(
                color: const Color(0xFFD4AF37).withOpacity(0.6),
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
