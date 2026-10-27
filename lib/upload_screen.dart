// lib/upload_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import 'config.dart';
import 'result_screen.dart';
import 'services/storage_service.dart';
import 'widgets/preview_image.dart';
import 'widgets/scan_zone.dart';
import 'widgets/particle_bg.dart';
import 'widgets/lumi_orb.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile?  _picked;
  bool    _isPicking   = false;
  bool    _isUploading = false;
  String? _error;
  String  _statusMsg   = '';
  Timer?  _statusTimer;
  int     _statusIndex = 0;
  String  _productType = 'unknown';
  String? _predictedBrand;
  String? _predictedProductName;
  bool    _showBrandConfirm = false;
  Map<String, dynamic>? _pendingResult;

  static const _productTypes = [
    ('Moisturizer',  Icons.water_drop_outlined),
    ('Serum',        Icons.science_outlined),
    ('Cleanser',     Icons.bubble_chart_outlined),
    ('Sunscreen',    Icons.wb_sunny_outlined),
    ('Toner',        Icons.opacity_outlined),
    ('Eye cream',    Icons.remove_red_eye_outlined),
    ('Body lotion',  Icons.accessibility_outlined),
    ('Hair product', Icons.content_cut_outlined),
    ('Other',        Icons.category_outlined),
  ];

  static const _scanMessages = [
    'Reading ingredient list…',
    'Identifying product type…',
    'Analyzing preservatives…',
    'Checking irritation profile…',
    'Evaluating fragrance components…',
    'Cross-referencing EU safety databases…',
    'Assessing skin compatibility…',
    'Finalizing analysis…',
  ];

  void _startStatusCycle() {
    _statusIndex = 0;
    setState(() => _statusMsg = _scanMessages[0]);
    _statusTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      if (!mounted) return;
      _statusIndex = (_statusIndex + 1) % _scanMessages.length;
      setState(() => _statusMsg = _scanMessages[_statusIndex]);
    });
  }

  void _stopStatusCycle() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  @override
  void dispose() {
    _stopStatusCycle();
    super.dispose();
  }

  Future<Uint8List> _compress(Uint8List raw) async {
    final src = img.decodeImage(raw);
    if (src == null) return raw;
    final oriented = img.bakeOrientation(src);
    const maxSide = 1000;
    final w = oriented.width, h = oriented.height;
    img.Image resized = oriented;
    if (w > maxSide || h > maxSide) {
      resized = img.copyResize(
        oriented,
        width:  w >= h ? maxSide : (w * maxSide ~/ h),
        height: h > w  ? maxSide : (h * maxSide ~/ w),
      );
    }
    return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
  }

  Future<void> _pickFrom(ImageSource source) async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 90);
      if (picked != null) setState(() { _picked = picked; _error = null; });
    } catch (e) {
      setState(() => _error = 'Could not open image picker.');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _showPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(color: const Color(0xFF333333), borderRadius: BorderRadius.circular(2))),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFFD4AF37)),
              title: const Text('Take a photo', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); _pickFrom(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFFD4AF37)),
              title: const Text('Choose from gallery', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); _pickFrom(ImageSource.gallery); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _analyze() async {
    if (_picked == null || _isUploading) return;
    setState(() { _isUploading = true; _error = null; });
    _startStatusCycle();

    try {
      final raw        = await _picked!.readAsBytes();
      final compressed = await _compress(raw);

      final uri = Uri.parse('$apiBase/upload');
      final req = http.MultipartRequest('POST', uri);
      req.files.add(http.MultipartFile.fromBytes(
        'image', compressed,
        filename: 'upload.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));
      // Send product type to backend
      req.fields['product_type'] = _productType;

      final streamed = await req.send().timeout(const Duration(seconds: 50));
      final res      = await http.Response.fromStream(streamed);

      if (res.statusCode == 429) throw Exception('Too many requests.');
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');

      final data    = jsonDecode(res.body) as Map<String, dynamic>;
      final count   = (data['ingredient_count'] as int?) ?? 0;
      final summary = (data['summary'] as String?) ?? '';

      if (count == 0 || summary.toLowerCase().contains('no ingredients list found')) {
        _stopStatusCycle();
        if (!mounted) return;
        setState(() => _error =
            "We couldn't find an ingredients list in this photo.\n\nTry a clearer, closer shot of the full ingredient list with good lighting.");
        return;
      }

      final concerns = (data['concerns'] as List<dynamic>?) ?? [];
      final score    = (data['smart_score'] as int?) ??
          (100 - ((concerns.length / count.clamp(1, 80)) * 100).clamp(0, 60).round());

      await StorageService.addScan(ScanRecord(
        date:            _formatDate(DateTime.now()),
        score:           score,
        ingredientCount: count,
        concernCount:    concerns.length,
        summary:         summary,
        fullResult:      data,
      ));

      if (!mounted) return;
      _stopStatusCycle();

      final brand = (data['brand'] as String?) ?? '';
      final productName = (data['product_name'] as String?) ?? '';

      if (brand.isNotEmpty || productName.isNotEmpty) {
        setState(() {
          _predictedBrand = brand;
          _predictedProductName = productName;
          _pendingResult = data;
          _showBrandConfirm = true;
        });
      } else {
        _navigateToResults(data);
      }
    } catch (e) {
      _stopStatusCycle();
      if (!mounted) return;
      setState(() => _error = e.toString().contains('timeout')
          ? 'Analysis timed out. Try a clearer photo.'
          : 'Analysis failed: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _navigateToResults(Map<String, dynamic> data) {
    setState(() { _showBrandConfirm = false; _pendingResult = null; });
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: anim, child: ResultScreen(result: data)),
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day} ${_month(d.month)} ${d.year}, ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  String _month(int m) => const ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080808),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text('VYOORA',
          style: GoogleFonts.cinzel(
            color: const Color(0xFFD4AF37), fontSize: 18,
            fontWeight: FontWeight.w600, letterSpacing: 4)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFD4AF37).withOpacity(0.1))),
      ),
      body: Stack(
        children: [
          ParticleBg(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Lumi orb
              Center(child: LumiOrb(scanning: _isUploading)),
              const SizedBox(height: 10),
              Center(
                child: Text('See beyond the label.',
                  style: GoogleFonts.cookie(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 17, fontStyle: FontStyle.italic)),
              ),
              const SizedBox(height: 24),

              // ── Product type selector ──
              Row(children: [
                Container(width: 3, height: 14, color: const Color(0xFFD4AF37).withOpacity(0.6),
                    margin: const EdgeInsets.only(right: 8)),
                Text('WHAT ARE YOU SCANNING?',
                  style: TextStyle(color: Colors.white.withOpacity(0.75),
                      fontSize: 12, letterSpacing: 2.5, fontWeight: FontWeight.w500)),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _productTypes.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final (label, icon) = _productTypes[i];
                    final selected = _productType == label.toLowerCase() ||
                        (_productType == 'unknown' && i == 0 && false);
                    final isSelected = _productType == label;
                    return GestureDetector(
                      onTap: () => setState(() => _productType = label),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFD4AF37).withOpacity(0.15)
                              : const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFD4AF37).withOpacity(0.6)
                                : const Color(0xFF2A2A2A),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon,
                              size: 13,
                              color: isSelected
                                  ? const Color(0xFFD4AF37)
                                  : Colors.white.withOpacity(0.3)),
                            const SizedBox(width: 5),
                            Text(label,
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFFD4AF37)
                                    : Colors.white.withOpacity(0.8),
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              )),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),

              // Error
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!,
                          style: const TextStyle(color: Colors.red, fontSize: 15, height: 1.5))),
                      GestureDetector(
                        onTap: () => setState(() => _error = null),
                        child: const Icon(Icons.close, size: 16, color: Colors.red)),
                    ],
                  ),
                ),

              // Scan zone
              Center(
                child: GestureDetector(
                  onTap: _isUploading ? null : _showPickerSheet,
                  child: _picked == null
                    ? const ScanZone()
                    : Stack(children: [
                        Container(
                          height: 300,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.4))),
                          clipBehavior: Clip.antiAlias,
                          child: PreviewImage(file: _picked),
                        ),
                        if (_isUploading)
                          Container(
                            height: 300,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: Colors.black.withOpacity(0.6)),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 32, height: 32,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4AF37))),
                                  const SizedBox(height: 14),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 400),
                                    child: Text(_statusMsg,
                                      key: ValueKey(_statusMsg),
                                      style: GoogleFonts.cookie(
                                        color: const Color(0xFFD4AF37),
                                        fontSize: 17, fontStyle: FontStyle.italic),
                                      textAlign: TextAlign.center),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ]),
                ),
              ),

              if (_picked != null && !_isUploading)
                TextButton.icon(
                  onPressed: _showPickerSheet,
                  icon: const Icon(Icons.swap_horiz, color: Color(0xFFD4AF37), size: 16),
                  label: const Text('Change image',
                      style: TextStyle(color: Color(0xFFD4AF37), fontSize: 15)),
                ),

              const SizedBox(height: 12),

              // Tip — moved closer to button
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline, color: Color(0xFFD4AF37), size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ensure all ingredients are visible for the most accurate analysis.',
                        style: GoogleFonts.cinzel(color: Colors.white.withOpacity(0.45), fontSize: 12, height: 1.5)),
                    ),
                  ],
                ),
              ),

              // Trust signal
              if (_picked != null && !_isUploading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Center(
                    child: Text('Analysis takes ~10 seconds',
                      style: GoogleFonts.cinzel(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 12, letterSpacing: 0.5)),
                  ),
                ),

              // Analyse button
              GestureDetector(
                onTap: (_picked != null && !_isUploading) ? _analyze : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 54,
                  decoration: BoxDecoration(
                    color: (_picked != null && !_isUploading)
                        ? const Color(0xFFD4AF37) : const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: (_picked != null && !_isUploading)
                        ? [BoxShadow(color: const Color(0xFFD4AF37).withOpacity(0.28),
                            blurRadius: 20, offset: const Offset(0, 6))]
                        : [],
                  ),
                  child: Center(
                    child: Text('Scan Ingredients',
                      style: GoogleFonts.cinzel(
                        color: (_picked != null && !_isUploading)
                            ? const Color(0xFF080808) : const Color(0xFF444444),
                        fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
          // Brand confirmation overlay
          if (_showBrandConfirm && _pendingResult != null)
            Container(
              color: Colors.black.withOpacity(0.85),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F0F),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search, color: Color(0xFFD4AF37), size: 32),
                        const SizedBox(height: 16),
                        if (_predictedBrand?.isNotEmpty == true) ...[
                          Text('Brand',
                            style: GoogleFonts.cinzel(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 11, letterSpacing: 2)),
                          const SizedBox(height: 4),
                          Text(_predictedBrand!,
                            style: GoogleFonts.cookie(
                              color: const Color(0xFFD4AF37),
                              fontSize: 28),
                            textAlign: TextAlign.center),
                        ],
                        if (_predictedProductName?.isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Text('Product',
                            style: GoogleFonts.cinzel(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 11, letterSpacing: 2)),
                          const SizedBox(height: 4),
                          Text(_predictedProductName!,
                            style: GoogleFonts.cinzel(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 13, height: 1.5),
                            textAlign: TextAlign.center),
                        ],
                        const SizedBox(height: 24),
                        Row(children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _navigateToResults(_pendingResult!),
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD4AF37),
                                  borderRadius: BorderRadius.circular(12)),
                                child: Center(child: Text("Let's Scan",
                                  style: GoogleFonts.cinzel(
                                    color: const Color(0xFF080808),
                                    fontSize: 13, fontWeight: FontWeight.w600))),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _showEditBrandDialog(),
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.4))),
                                child: Center(child: Text('Edit',
                                  style: GoogleFonts.cinzel(
                                    color: const Color(0xFFD4AF37),
                                    fontSize: 13, fontWeight: FontWeight.w600))),
                              ),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showEditBrandDialog() {
    final brandCtrl = TextEditingController(text: _predictedBrand ?? '');
    final productCtrl = TextEditingController(text: _predictedProductName ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F0F),
        title: Text('Edit product info',
          style: GoogleFonts.cinzel(color: const Color(0xFFD4AF37), fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: brandCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Brand',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: const Color(0xFFD4AF37).withOpacity(0.3))),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFD4AF37)))),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: productCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Product name',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: const Color(0xFFD4AF37).withOpacity(0.3))),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFD4AF37)))),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (_pendingResult != null) {
                _pendingResult!['brand'] = brandCtrl.text;
                _pendingResult!['product_name'] = productCtrl.text;
                _navigateToResults(_pendingResult!);
              }
            },
            child: Text('Confirm', style: const TextStyle(color: Color(0xFFD4AF37)))),
        ],
      ),
    );
  }
}
