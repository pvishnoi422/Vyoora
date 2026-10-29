import 'package:flutter/material.dart';
import '../../models/fashion/domain.dart';
import '../../services/tryon_repository.dart';
import '../../services/wardrobe_session.dart';
import 'tryon_widgets.dart';
import 'look_actions.dart';

class SavedLooksScreen extends StatelessWidget {
  final WardrobeSession? session;
  final TryOnRepository? repository;
  const SavedLooksScreen({super.key, this.session, this.repository});
  @override
  Widget build(BuildContext context) {
    final identity = session ?? WardrobeSession.instance;
    return FashionAccountGate(
      session: identity,
      title: 'My Looks',
      builder: () =>
          _Looks(repository: repository ?? TryOnRepository(session: identity)),
    );
  }
}

class _Looks extends StatefulWidget {
  final TryOnRepository repository;
  const _Looks({required this.repository});
  @override
  State<_Looks> createState() => _LooksState();
}

class _LooksState extends State<_Looks> {
  List<SavedLook> items = [];
  bool loading = true;
  String? error, next;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await widget.repository.looks(pageToken: more ? next : null);
      if (mounted) {
        setState(() {
          items = more ? [...items, ...page.items] : page.items;
          next = page.nextPageToken;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = fashionError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> open(SavedLook look) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FashionAccountGate(
          session: widget.repository.session,
          title: 'My Looks',
          builder: () => widget.repository.session.uid == look.ownerId
              ? _LookDetail(look: look, repository: widget.repository)
              : const Scaffold(
                  body: Center(
                    child: Text('This look belongs to a different account.'),
                  ),
                ),
        ),
      ),
    );
    if (mounted) load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My Looks'),
      actions: [
        IconButton(
          tooltip: 'Refresh looks',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Your private saved previews stay for 30 days from saving, unless you delete them or their reference photo first.',
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null) ...[
          Text(error!, key: const Key('looks-error')),
          TextButton(onPressed: load, child: const Text('Retry')),
        ],
        if (!loading && error == null && items.isEmpty) ...[
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No saved looks yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pushNamed(context, '/fashion/try-on'),
            child: const Text('Create a look'),
          ),
        ],
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 300,
            mainAxisExtent: 340,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemBuilder: (_, index) {
            final look = items[index];
            return Card(
              child: InkWell(
                key: ValueKey('look-${look.id}'),
                onTap: () => open(look),
                child: Column(
                  children: [
                    Expanded(
                      child: PrivatePhoto(
                        identity: 'saved-${look.id}',
                        load: () => widget.repository.lookImage(look.id),
                      ),
                    ),
                    ListTile(
                      title: Text(look.title),
                      subtitle: Text(
                        'Expires ${photoDate(look.preview!.expiresAt!)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        if (next != null)
          TextButton(
            onPressed: loading ? null : () => load(more: true),
            child: const Text('Load more looks'),
          ),
      ],
    ),
  );
}

class _LookDetail extends StatefulWidget {
  final SavedLook look;
  final TryOnRepository repository;
  const _LookDetail({required this.look, required this.repository});
  @override
  State<_LookDetail> createState() => _LookDetailState();
}

class _LookDetailState extends State<_LookDetail> {
  bool deleting = false;
  String? error;
  Future<void> delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this look?'),
        content: const Text(
          'This permanently removes Vyoora’s saved copy. Photos and shared copies remain outside Vyoora.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep look'),
          ),
          FilledButton(
            key: const Key('look-confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete look'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      deleting = true;
      error = null;
    });
    try {
      await widget.repository.deleteLook(widget.look.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          deleting = false;
          error = fashionError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.look.title)),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AspectRatio(
          aspectRatio: 0.8,
          child: PrivatePhoto(
            identity: 'saved-${widget.look.id}',
            load: () => widget.repository.lookImage(widget.look.id),
          ),
        ),
        const Text(
          'AI-generated visualization. Fit, size and garment details can vary.',
        ),
        LookExportActions(
          load: () => widget.repository.lookImage(widget.look.id),
        ),
        if (error != null) Text(error!),
        TextButton.icon(
          key: const Key('look-delete'),
          onPressed: deleting ? null : delete,
          icon: const Icon(Icons.delete_outline),
          label: Text(deleting ? 'Deleting…' : 'Delete look'),
        ),
      ],
    ),
  );
}

class SaveLookButton extends StatefulWidget {
  final String jobId;
  final TryOnRepository repository;
  const SaveLookButton({
    super.key,
    required this.jobId,
    required this.repository,
  });
  @override
  State<SaveLookButton> createState() => _SaveLookButtonState();
}

class _SaveLookButtonState extends State<SaveLookButton> {
  bool busy = false, saved = false;
  String? error;
  Future<void> save() async {
    final title = TextEditingController(text: 'My look');
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Save to My Looks'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Look name'),
              ),
              const Text(
                'Save a private copy for 30 days. It stays when the reference photo expires automatically. Deleting the reference photo yourself removes its saved looks too. You can delete this look at any time.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('look-confirm-save'),
            onPressed: () {
              if (title.text.trim().isNotEmpty) {
                Navigator.pop(context, title.text.trim());
              }
            },
            child: const Text('Save private look'),
          ),
        ],
      ),
    );
    // Dialog field can still be completing its closing animation.
    // The route owns the field until its reverse transition completes.
    Future<void>.delayed(const Duration(seconds: 1), title.dispose);
    if (name == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.saveLook(widget.jobId, name);
      if (mounted) setState(() => saved = true);
    } catch (e) {
      if (mounted) setState(() => error = fashionError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      FilledButton.icon(
        key: const Key('look-save'),
        onPressed: busy || saved ? null : save,
        icon: const Icon(Icons.bookmark_add_outlined),
        label: Text(
          saved
              ? 'Saved to My Looks'
              : busy
              ? 'Saving…'
              : 'Save to My Looks',
        ),
      ),
      TextButton(
        onPressed: () => Navigator.pushNamed(context, '/fashion/saved-looks'),
        child: const Text('Open My Looks'),
      ),
      if (error != null) Text(error!),
    ],
  );
}
