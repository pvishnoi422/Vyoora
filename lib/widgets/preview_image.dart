// lib/widgets/preview_image.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PreviewImage extends StatefulWidget {
  final XFile? file;
  const PreviewImage({super.key, required this.file});

  @override
  State<PreviewImage> createState() => _PreviewImageState();
}

class _PreviewImageState extends State<PreviewImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PreviewImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file?.path != widget.file?.path) _load();
  }

  Future<void> _load() async {
    final f = widget.file;
    if (f == null) {
      setState(() => _bytes = null);
      return;
    }
    if (!kIsWeb) {
      final b = await f.readAsBytes();
      if (mounted) setState(() => _bytes = b);
    } else {
      // On web we’ll render via blob URL below, so no bytes needed.
      setState(() => _bytes = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    if (f == null) return const SizedBox.shrink();

    // Web: blob/object URL -> Image.network
    if (kIsWeb) return Image.network(f.path, fit: BoxFit.cover);

    // Mobile/Desktop: bytes -> Image.memory (avoids dart:io on web builds)
    if (_bytes == null) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Image.memory(_bytes!, fit: BoxFit.cover);
  }
}
