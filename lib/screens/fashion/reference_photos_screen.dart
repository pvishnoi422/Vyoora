import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/fashion/domain.dart';
import '../../services/tryon_repository.dart';
import '../../services/wardrobe_session.dart';
import 'tryon_widgets.dart';

class ReferencePhotosScreen extends StatefulWidget {
  final WardrobeSession? session;
  final TryOnRepository? repository;
  final Future<Uint8List?> Function()? pickPhoto;
  const ReferencePhotosScreen({
    super.key,
    this.session,
    this.repository,
    this.pickPhoto,
  });
  @override
  State<ReferencePhotosScreen> createState() => _ReferencePhotosScreenState();
}

class _ReferencePhotosScreenState extends State<ReferencePhotosScreen> {
  late final session = widget.session ?? WardrobeSession.instance;
  late final repository =
      widget.repository ?? TryOnRepository(session: session);
  @override
  Widget build(BuildContext context) => FashionAccountGate(
    session: session,
    title: 'Reference photos',
    builder: () => _ReferenceCollection(
      repository: repository,
      pickPhoto: widget.pickPhoto,
    ),
  );
}

class _ReferenceCollection extends StatefulWidget {
  final TryOnRepository repository;
  final Future<Uint8List?> Function()? pickPhoto;
  const _ReferenceCollection({required this.repository, this.pickPhoto});
  @override
  State<_ReferenceCollection> createState() => _ReferenceCollectionState();
}

class _ReferenceCollectionState extends State<_ReferenceCollection> {
  List<ReferencePhoto> photos = [];
  bool loading = true, busy = false, uploading = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await widget.repository.references();
      if (mounted) setState(() => photos = values);
    } catch (e) {
      if (mounted) setState(() => error = fashionError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> upload() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final photo = await chooseReferencePhoto(
        context,
        widget.repository,
        pickPhoto: widget.pickPhoto,
        onUpload: () {
          if (mounted) setState(() => uploading = true);
        },
      );
      if (photo != null && mounted) setState(() => photos.insert(0, photo));
    } catch (e) {
      if (mounted) setState(() => error = fashionError(e));
    } finally {
      if (mounted)
        setState(() {
          busy = false;
          uploading = false;
        });
    }
  }

  Future<void> remove(ReferencePhoto photo) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this reference photo?'),
        content: const Text(
          'This blocks new processing, cancels its generations, and permanently removes this photo and its previews from Vyoora. Processing already sent to Google cannot be recalled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep photo'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete photo'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.deleteReference(photo.id);
      if (mounted) setState(() => photos.removeWhere((p) => p.id == photo.id));
    } catch (e) {
      if (mounted) setState(() => error = fashionError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Reference photos'),
      actions: [
        IconButton(
          tooltip: 'Refresh photos',
          onPressed: loading || busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      key: const Key('add-reference-photo'),
      onPressed: busy || loading ? null : upload,
      icon: const Icon(Icons.add_a_photo_outlined),
      label: Text(uploading ? 'Uploading…' : 'Add photo'),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
      children: [
        Text(
          'A private space for your photos',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Photos expire after seven days. You choose when to send a photo to Google for a try-on.',
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(error!, key: const Key('reference-error')),
          ),
        if (loading || uploading) const LinearProgressIndicator(),
        if (!loading && photos.isEmpty && error == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('No reference photos yet.'),
          ),
        for (final photo in photos)
          Card(
            key: ValueKey(photo.id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SizedBox(
                    height: 230,
                    child: PrivatePhoto(
                      identity: photo.id,
                      load: () => widget.repository.referenceImage(photo.id),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Added ${photoDate(photo.createdAt)}'),
                  Text('Expires ${photoDate(photo.expiresAt)}'),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.pushNamed(
                          context,
                          '/fashion/try-on',
                          arguments: {'referenceId': photo.id},
                        ),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Try on'),
                      ),
                      TextButton.icon(
                        onPressed: busy ? null : () => remove(photo),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete photo'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
