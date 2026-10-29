import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/fashion/domain.dart';
import '../../services/tryon_repository.dart';
import '../../services/wardrobe_session.dart';

class PrivatePhoto extends StatefulWidget {
  final String identity;
  final Future<Uint8List> Function() load;
  final BoxFit fit;
  const PrivatePhoto({
    super.key,
    required this.identity,
    required this.load,
    this.fit = BoxFit.contain,
  });
  @override
  State<PrivatePhoto> createState() => _PrivatePhotoState();
}

class _PrivatePhotoState extends State<PrivatePhoto> {
  late Future<Uint8List> future = widget.load();
  @override
  void didUpdateWidget(covariant PrivatePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) future = widget.load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return Center(
          child: TextButton.icon(
            onPressed: () => setState(() => future = widget.load()),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry photo'),
          ),
        );
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      return Image.memory(
        snapshot.data!,
        fit: widget.fit,
        cacheWidth: 1000,
        errorBuilder: (_, _, _) =>
            const Center(child: Text('Photo unavailable')),
      );
    },
  );
}

class FashionAccountGate extends StatelessWidget {
  final WardrobeSession session;
  final String title;
  final Widget Function() builder;
  const FashionAccountGate({
    super.key,
    required this.session,
    required this.title,
    required this.builder,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      if (session.signedIn)
        return KeyedSubtree(key: ValueKey(session.uid), child: builder());
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48),
                const SizedBox(height: 20),
                const Text(
                  'Sign in through your wardrobe to use your private photos and try-on.',
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pushNamed(context, '/wardrobe'),
                  child: const Text('Open wardrobe'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String photoDate(DateTime value) {
  final date = value.toLocal();
  return '${date.month}/${date.day}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String fashionError(Object error) => error is WardrobeFailure
    ? error.message
    : 'Could not complete this request. Please try again.';

Future<ReferencePhoto?> chooseReferencePhoto(
  BuildContext context,
  TryOnRepository repository, {
  Future<Uint8List?> Function()? pickPhoto,
  VoidCallback? onUpload,
}) async {
  Uint8List? bytes;
  if (pickPhoto != null) {
    bytes = await pickPhoto();
  } else {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose photo'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 90,
    );
    if (file == null) return null;
    if (await file.length() > 5 * 1024 * 1024)
      throw const WardrobeFailure('Choose a photo smaller than 5 MB.');
    bytes = await file.readAsBytes();
  }
  if (bytes == null || !context.mounted) return null;
  if (bytes.length > 5 * 1024 * 1024)
    throw const WardrobeFailure('Choose a photo smaller than 5 MB.');
  final consent = await showDialog<bool>(
    context: context,
    builder: (_) => _ReferenceConsent(photo: bytes!),
  );
  if (consent != true || !context.mounted) return null;
  onUpload?.call();
  return repository.uploadReference(bytes);
}

class _ReferenceConsent extends StatefulWidget {
  final Uint8List photo;
  const _ReferenceConsent({required this.photo});
  @override
  State<_ReferenceConsent> createState() => _ReferenceConsentState();
}

class _ReferenceConsentState extends State<_ReferenceConsent> {
  bool permission = false, processing = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Your photo, your choice'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 160,
              child: Image.memory(
                widget.photo,
                fit: BoxFit.contain,
                cacheWidth: 400,
                errorBuilder: (_, _, _) => const Icon(Icons.photo_outlined),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Use a clear photo of one adult. Vyoora uses Google Cloud for private storage and Google’s Gemini image model for try-on processing. Your reference photo and unsaved previews become unavailable after seven days; automatic storage cleanup can take longer. Deleting the reference photo blocks new processing and removes its Vyoora previews and saved looks. Saved looks have a separate 30-day limit. Google may keep processing data for abuse monitoring for up to 30 days; Vyoora cannot delete Google’s logs or recall processing already sent.',
            ),
            CheckboxListTile(
              key: const Key('reference-permission'),
              contentPadding: EdgeInsets.zero,
              value: permission,
              onChanged: (v) => setState(() => permission = v!),
              title: const Text(
                'I am 18 or older. This is my photo, or I have the adult pictured’s permission.',
              ),
            ),
            CheckboxListTile(
              key: const Key('reference-processing'),
              contentPadding: EdgeInsets.zero,
              value: processing,
              onChanged: (v) => setState(() => processing = v!),
              title: const Text(
                'I agree to private storage and processing by Google Vertex AI when I request a try-on.',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/fashion/privacy'),
              child: const Text('Vyoora photo privacy'),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://docs.cloud.google.com/gemini-enterprise-agent-platform/resources/zero-data-retention',
                ),
              ),
              child: const Text('Google Cloud data use'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('reference-upload-consented'),
        onPressed: permission && processing
            ? () => Navigator.pop(context, true)
            : null,
        child: const Text('Upload private photo'),
      ),
    ],
  );
}
