// lib/upload_screen.dart

// Dart core
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File;

// Flutter
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Packages
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // MediaType
import 'package:image_picker/image_picker.dart';

// App files
import 'config.dart';
import 'result_screen.dart';
import 'components/vyoora_scaffold.dart';
import 'components/chat_screen.dart';
import 'utils/image_prep.dart'; // <-- ONLY import. Do not define here.

class PreviewImage extends StatelessWidget {
  final XFile? file;
  const PreviewImage({super.key, this.file});

  @override
  Widget build(BuildContext context) {
    if (file == null) return const SizedBox();
    if (kIsWeb) {
      return Image.network(file!.path, height: 200, fit: BoxFit.cover);
    } else {
      return Image.file(File(file!.path), height: 200, fit: BoxFit.cover);
    }
  }
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({Key? key}) : super(key: key);

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final ImagePicker _picker = ImagePicker();

  XFile? _picked;
  bool _isPicking = false;
  bool _isUploading = false;
  String? _error;

  Future<void> _pickImage() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() {
          _picked = picked;
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = 'Image pick failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _analyze() async {
  if (_picked == null || _isUploading) return;

  setState(() => _isUploading = true);

  try {
    final uri = Uri.parse('$apiBase/upload');
    final req = http.MultipartRequest('POST', uri);

    // Read original bytes (TEMP: no preprocessing)
    final Uint8List rawBytes = await _picked!.readAsBytes();

    req.files.add(
      http.MultipartFile.fromBytes(
        'image', // must match Flask backend
        rawBytes,
        filename: 'upload.jpg',
        contentType: MediaType('image', 'jpeg'),
      ),
    );

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode != 200) {
      throw Exception('Server error ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ResultScreen(result: data)),
    );
  } catch (e) {
    if (!mounted) return;
    setState(() => _error = 'Analysis failed: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Upload failed: $e')),
    );
  } finally {
    if (mounted) setState(() => _isUploading = false);
  }
}

  @override
  Widget build(BuildContext context) {
    final body = Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: _picked == null
                      ? const _EmptyPicker()
                      : PreviewImage(file: _picked),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: (_picked != null && !_isUploading) ? _analyze : null,
              icon: _isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_isUploading ? 'Analyzing…' : 'Upload & Analyze'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 120),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16 + 56,
          child: FloatingActionButton(
            tooltip: 'Ask Vyoora',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatScreen()),
            ),
            child: const Icon(Icons.chat_bubble_outline),
          ),
        ),
      ],
    );

    return VyooraScaffold(
      title: 'Vyoora',
      body: body,
      showChatFab: false,
    );
  }
}

class _EmptyPicker extends StatelessWidget {
  const _EmptyPicker();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 48),
          SizedBox(height: 8),
          Text('Tap to select product image'),
        ],
      ),
    );
  }
}
