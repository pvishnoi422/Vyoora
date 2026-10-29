import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/fashion/domain.dart';
import '../../services/wardrobe_repository.dart';
import '../../services/wardrobe_session.dart';
import '../../services/tryon_repository.dart' show tryOnCategories;
import 'account_actions.dart';

String wardrobeError(Object error) => error is WardrobeFailure
    ? error.message
    : 'Could not reach your wardrobe. Please try again.';

class WardrobeScreen extends StatefulWidget {
  final WardrobeSession? session;
  final WardrobeRepository? repository;
  final Future<Uint8List?> Function()? pickPhoto;
  const WardrobeScreen({
    super.key,
    this.session,
    this.repository,
    this.pickPhoto,
  });
  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  late final session = widget.session ?? WardrobeSession.instance;
  late final repository =
      widget.repository ?? WardrobeRepository(session: session);
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => !session.signedIn
        ? _SignIn(session: session, configured: repository.configured)
        : _WardrobeCollection(
            key: ValueKey(session.uid),
            repository: repository,
            session: session,
            pickPhoto: widget.pickPhoto,
          ),
  );
}

class _SignIn extends StatefulWidget {
  final WardrobeSession session;
  final bool configured;
  const _SignIn({required this.session, required this.configured});
  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false, create = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (email.text.trim().isEmpty || password.text.length < 6) {
      setState(
        () => error =
            'Enter your email and a password of at least six characters.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.signIn(email.text, password.text, create: create);
    } catch (e) {
      if (mounted) setState(() => error = wardrobeError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Wardrobe')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.checkroom_outlined, size: 64),
            const SizedBox(height: 24),
            Text(
              'Your wardrobe starts here',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Sign in to add clothes and keep your photos private to your account.',
            ),
            if (!widget.configured)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Wardrobe sign-in is not configured in this build.',
                ),
              ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('wardrobe-email'),
              controller: email,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              key: const Key('wardrobe-password'),
              controller: password,
              enabled: !busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (_) {
                if (!busy && widget.configured) submit();
              },
            ),
            const SizedBox(height: 20),
            if (error != null) Text(error!),
            FilledButton(
              key: const Key('wardrobe-sign-in'),
              onPressed: busy || !widget.configured ? null : submit,
              child: Text(
                busy
                    ? 'Please wait…'
                    : create
                    ? 'Create account'
                    : 'Sign in',
              ),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      create = !create;
                      error = null;
                    }),
              child: Text(
                create
                    ? 'Already have an account? Sign in'
                    : 'Create an account',
              ),
            ),
            if (create)
              const Text(
                'Verify your email before uploading. Check your inbox after creating your account.',
              ),
          ],
        ),
      ),
    ),
  );
}

class _WardrobeCollection extends StatefulWidget {
  final WardrobeSession session;
  final WardrobeRepository repository;
  final Future<Uint8List?> Function()? pickPhoto;
  const _WardrobeCollection({
    super.key,
    required this.session,
    required this.repository,
    this.pickPhoto,
  });
  @override
  State<_WardrobeCollection> createState() => _WardrobeCollectionState();
}

class _WardrobeCollectionState extends State<_WardrobeCollection> {
  final items = <WardrobeItem>[];
  final deleting = <String>{};
  bool loading = true, uploading = false, choosingPhoto = false;
  String? error, nextPage;
  int loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false, bool refreshToken = false}) async {
    if (uploading || choosingPhoto || deleting.isNotEmpty) return;
    final generation = ++loadGeneration;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (refreshToken) await widget.session.token(forceRefresh: true);
      final page = await widget.repository.list(
        pageToken: more ? nextPage : null,
      );
      if (!mounted || generation != loadGeneration) return;
      setState(() {
        if (!more) items.clear();
        for (final item in page.items) {
          if (!items.any((existing) => existing.id == item.id)) items.add(item);
        }
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        nextPage = page.nextPageToken;
      });
    } catch (e) {
      if (mounted && generation == loadGeneration)
        setState(() => error = wardrobeError(e));
    } finally {
      if (mounted && generation == loadGeneration)
        setState(() => loading = false);
    }
  }

  Future<void> add() async {
    setState(() {
      choosingPhoto = true;
      error = null;
    });
    try {
      Uint8List? bytes;
      if (widget.pickPhoto != null) {
        bytes = await widget.pickPhoto!();
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
        if (source == null) return;
        final file = await ImagePicker().pickImage(
          source: source,
          maxWidth: 2000,
          maxHeight: 2000,
          imageQuality: 90,
        );
        if (file == null) return;
        if (await file.length() > 5 * 1024 * 1024)
          throw const WardrobeFailure('Choose a photo smaller than 5 MB.');
        bytes = await file.readAsBytes();
      }
      if (bytes == null || !mounted) return;
      final details = await showDialog<_GarmentDetails>(
        context: context,
        builder: (_) => const _AddGarmentDialog(),
      );
      if (details == null || !mounted) return;
      setState(() => uploading = true);
      final item = await widget.repository.upload(
        bytes: bytes,
        name: details.name,
        category: details.category,
        color: details.color,
      );
      if (!mounted) return;
      setState(() => items.insert(0, item));
    } catch (e) {
      if (mounted) setState(() => error = wardrobeError(e));
    } finally {
      if (context.mounted)
        setState(() {
          uploading = false;
          choosingPhoto = false;
        });
    }
  }

  Future<void> remove(WardrobeItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${item.name}?'),
        content: const Text(
          'This permanently removes the garment and its private photo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      deleting.add(item.id);
      error = null;
    });
    try {
      await widget.repository.delete(item.id);
      if (mounted)
        setState(() => items.removeWhere((existing) => existing.id == item.id));
    } catch (e) {
      if (mounted) setState(() => error = wardrobeError(e));
    } finally {
      if (mounted) setState(() => deleting.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Wardrobe'),
      actions: [
        IconButton(
          key: const Key('wardrobe-refresh'),
          tooltip: 'Refresh',
          onPressed:
              loading || uploading || choosingPhoto || deleting.isNotEmpty
              ? null
              : () => load(refreshToken: true),
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          key: const Key('wardrobe-sign-out'),
          tooltip: 'Sign out',
          onPressed: widget.session.signOut,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      key: const Key('add-garment'),
      onPressed: uploading || loading || choosingPhoto || deleting.isNotEmpty
          ? null
          : add,
      icon: uploading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(),
            )
          : const Icon(Icons.add),
      label: Text(uploading ? 'Uploading…' : 'Add garment'),
    ),
    body: RefreshIndicator(
      onRefresh: () => load(refreshToken: true),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.session.email ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Text('Your clothes. Your private collection.'),
                  AccountActions(repository: widget.repository),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(error!, key: const Key('wardrobe-error')),
                    ),
                  if (error?.contains('Verify your email') ?? false)
                    TextButton(
                      onPressed: () async {
                        try {
                          await widget.session.sendVerification();
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Verification email sent.'),
                              ),
                            );
                        } catch (e) {
                          if (mounted) setState(() => error = wardrobeError(e));
                        }
                      },
                      child: const Text('Resend verification email'),
                    ),
                ],
              ),
            ),
          ),
          if (loading)
            const SliverToBoxAdapter(child: LinearProgressIndicator()),
          if (!loading && items.isEmpty && error == null)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.checkroom_outlined, size: 64),
                    SizedBox(height: 20),
                    Text('No garments yet'),
                    SizedBox(height: 12),
                    Text('Add your first photo to start your wardrobe.'),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) => SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: (constraints.crossAxisExtent / 190)
                      .floor()
                      .clamp(2, 6),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 300,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final item = items[index];
                  return Card(
                    key: ValueKey(item.id),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _GarmentPhoto(
                            key: ValueKey('photo-${item.id}'),
                            item: item,
                            repository: widget.repository,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      [
                                        item.category.name,
                                        if (item.color != null) item.color!,
                                      ].join(' · '),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Delete ${item.name}',
                                onPressed:
                                    loading || uploading || deleting.isNotEmpty
                                    ? null
                                    : () => remove(item),
                                icon: deleting.contains(item.id)
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(),
                                      )
                                    : const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                        if (tryOnCategories.contains(item.category))
                          TextButton.icon(
                            onPressed:
                                loading ||
                                    uploading ||
                                    choosingPhoto ||
                                    deleting.isNotEmpty
                                ? null
                                : () => Navigator.pushNamed(
                                    context,
                                    '/fashion/try-on',
                                    arguments: item.id,
                                  ),
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('Try on'),
                          ),
                      ],
                    ),
                  );
                }, childCount: items.length),
              ),
            ),
          ),
          if (nextPage != null)
            SliverToBoxAdapter(
              child: TextButton(
                onPressed: loading ? null : () => load(more: true),
                child: const Text('Load more'),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    ),
  );
}

class _GarmentPhoto extends StatefulWidget {
  final WardrobeItem item;
  final WardrobeRepository repository;
  const _GarmentPhoto({
    super.key,
    required this.item,
    required this.repository,
  });
  @override
  State<_GarmentPhoto> createState() => _GarmentPhotoState();
}

class _GarmentPhotoState extends State<_GarmentPhoto> {
  late Future<Uint8List> image = widget.repository.image(widget.item.id);
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: image,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return Center(
          child: IconButton(
            tooltip: 'Retry photo',
            onPressed: () =>
                setState(() => image = widget.repository.image(widget.item.id)),
            icon: const Icon(Icons.refresh),
          ),
        );
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      return Image.memory(
        snapshot.data!,
        fit: BoxFit.cover,
        cacheWidth: 480,
        gaplessPlayback: false,
        semanticLabel: widget.item.name,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
      );
    },
  );
}

class _GarmentDetails {
  final String name, color;
  final GarmentCategory category;
  const _GarmentDetails(this.name, this.color, this.category);
}

class _AddGarmentDialog extends StatefulWidget {
  const _AddGarmentDialog();
  @override
  State<_AddGarmentDialog> createState() => _AddGarmentDialogState();
}

class _AddGarmentDialogState extends State<_AddGarmentDialog> {
  final name = TextEditingController(), color = TextEditingController();
  final form = GlobalKey<FormState>();
  GarmentCategory category = GarmentCategory.top;
  bool consent = false;
  @override
  void dispose() {
    name.dispose();
    color.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add garment'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('garment-name'),
              controller: name,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Name your garment'
                  : null,
            ),
            DropdownButtonFormField<GarmentCategory>(
              initialValue: category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: GarmentCategory.values
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value.name)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => category = value!),
            ),
            TextFormField(
              key: const Key('garment-color'),
              controller: color,
              maxLength: 50,
              decoration: const InputDecoration(labelText: 'Color (optional)'),
            ),
            CheckboxListTile(
              key: const Key('garment-consent'),
              contentPadding: EdgeInsets.zero,
              value: consent,
              onChanged: (value) => setState(() => consent = value!),
              title: const Text('Store this photo privately in my wardrobe.'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('save-garment'),
        onPressed: !consent
            ? null
            : () {
                if (form.currentState!.validate())
                  Navigator.pop(
                    context,
                    _GarmentDetails(
                      name.text.trim(),
                      color.text.trim(),
                      category,
                    ),
                  );
              },
        child: const Text('Upload'),
      ),
    ],
  );
}
