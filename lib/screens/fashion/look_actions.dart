import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/look_export.dart';

class LookExportActions extends StatefulWidget {
  final Future<Uint8List> Function() load;
  final LookExport? exporter;
  const LookExportActions({super.key, required this.load, this.exporter});
  @override
  State<LookExportActions> createState() => _LookExportActionsState();
}

class _LookExportActionsState extends State<LookExportActions> {
  bool busy = false;
  String? message;
  late final exporter = widget.exporter ?? LookExport();
  Future<void> export(bool share) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final bytes = await widget.load();
      // Signing out/unmounting while fetching must not open native UI.
      if (!mounted) return;
      if (share) {
        final completed = await exporter.share(bytes);
        if (mounted) {
          setState(() => message = completed ? 'Shared' : 'Sharing cancelled');
        }
      } else {
        await exporter.save(bytes);
        if (mounted) setState(() => message = 'Saved to Photos');
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => message = switch (error.code) {
            'permission_denied' =>
              'Photos access is off. Allow adding photos in iOS Settings, then try again.',
            'ios_required' => 'Open the iOS app to save to Photos or share.',
            'ios_version' => 'Save to Photos requires iOS 14 or later.',
            'busy' => 'Finish the current share first.',
            _ => 'Could not export this image. Please try again.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Could not load this image. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (exporter.supported)
        Wrap(
          spacing: 12,
          children: [
            OutlinedButton.icon(
              key: const Key('look-save-photos'),
              onPressed: busy ? null : () => export(false),
              icon: const Icon(Icons.save_alt),
              label: const Text('Save to Photos'),
            ),
            OutlinedButton.icon(
              key: const Key('look-share'),
              onPressed: busy ? null : () => export(true),
              icon: const Icon(Icons.ios_share),
              label: const Text('Share'),
            ),
          ],
        )
      else
        const Text('Save to Photos and sharing are available in the iOS app.'),
      const Text(
        'Exports include a Vyoora AI-preview watermark. Copies in Photos or other apps are outside Vyoora and are not removed when you delete a look.',
      ),
      if (busy) const LinearProgressIndicator(),
      if (message != null) Text(message!, key: const Key('look-export-status')),
    ],
  );
}
