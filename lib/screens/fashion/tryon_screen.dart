import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/fashion/domain.dart';
import '../../models/fashion/tryon_job.dart';
import '../../services/tryon_repository.dart';
import '../../services/wardrobe_session.dart';
import '../../services/wardrobe_repository.dart';
import 'tryon_widgets.dart';
import 'saved_looks_screen.dart';
import 'look_actions.dart';

class TryOnScreen extends StatefulWidget {
  final String? initialGarmentId;
  final String? initialReferenceId;
  final WardrobeSession? session;
  final TryOnRepository? repository;
  final Future<Uint8List?> Function()? pickReferencePhoto;
  const TryOnScreen({
    super.key,
    this.initialGarmentId,
    this.initialReferenceId,
    this.session,
    this.repository,
    this.pickReferencePhoto,
  });
  @override
  State<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends State<TryOnScreen> {
  late final session = widget.session ?? WardrobeSession.instance;
  late final repository =
      widget.repository ?? TryOnRepository(session: session);
  @override
  Widget build(BuildContext context) => FashionAccountGate(
    session: session,
    title: 'Try on',
    builder: () => _TryOnExperience(
      repository: repository,
      initialGarmentId: widget.initialGarmentId,
      initialReferenceId: widget.initialReferenceId,
      pickReferencePhoto: widget.pickReferencePhoto,
    ),
  );
}

class _TryOnExperience extends StatefulWidget {
  final TryOnRepository repository;
  final String? initialGarmentId;
  final String? initialReferenceId;
  final Future<Uint8List?> Function()? pickReferencePhoto;
  const _TryOnExperience({
    required this.repository,
    this.initialGarmentId,
    this.initialReferenceId,
    this.pickReferencePhoto,
  });
  @override
  State<_TryOnExperience> createState() => _TryOnExperienceState();
}

class _TryOnExperienceState extends State<_TryOnExperience> {
  List<WardrobeItem> garments = [];
  List<ReferencePhoto> photos = [];
  String? garmentId, referenceId, nextPage, requestId, error, pollError;
  TryOnAvailability? limits;
  TryOnJob? current;
  Timer? timer;
  bool loading = true,
      busy = false,
      uploading = false,
      cancelling = false,
      consent = false,
      uncertain = false;
  bool get locked =>
      busy || cancelling || uncertain || (current?.active ?? false);
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (busy || cancelling) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.repository.list(),
        widget.repository.references(),
        widget.repository.availability(),
        widget.repository.jobs(),
      ]);
      if (!mounted) return;
      final page = results[0] as WardrobePage;
      setState(() {
        garments = page.items
            .where((g) => tryOnCategories.contains(g.category))
            .toList();
        nextPage = page.nextPageToken;
        photos = results[1] as List<ReferencePhoto>;
        limits = results[2] as TryOnAvailability;
        if (!garments.any((g) => g.id == garmentId)) {
          garmentId = garments.any((g) => g.id == widget.initialGarmentId)
              ? widget.initialGarmentId
              : garments.firstOrNull?.id;
        }
        if (!photos.any((p) => p.id == referenceId)) {
          referenceId = photos.any((p) => p.id == widget.initialReferenceId)
              ? widget.initialReferenceId
              : photos.firstOrNull?.id;
        }
      });
      final jobs = results[3] as List<TryOnJob>;
      if (current != null) {
        apply(await widget.repository.job(current!.id));
      } else {
        final active = jobs.where((job) => job.active).firstOrNull;
        if (active != null) {
          apply(active);
        } else if (widget.initialGarmentId == null &&
            widget.initialReferenceId == null &&
            jobs.isNotEmpty) {
          apply(jobs.first);
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = fashionError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void apply(TryOnJob job) {
    if (!mounted) return;
    // A delayed poll cannot reverse an acknowledged cancellation/completion.
    if (current?.id == job.id && !(current?.active ?? true) && job.active)
      return;
    setState(() {
      current = job;
      requestId = job.id;
      uncertain = false;
      pollError = null;
    });
    timer?.cancel();
    if (job.active) timer = Timer(const Duration(seconds: 2), poll);
  }

  Future<void> poll() async {
    if (!mounted || current == null) return;
    final id = current!.id;
    try {
      final job = await widget.repository.job(id);
      if (!mounted || current?.id != id) return;
      apply(job);
      if (!job.active) await refreshLimits();
    } catch (_) {
      if (!mounted || current?.id != id || !(current?.active ?? false)) return;
      setState(
        () => pollError =
            'Connection interrupted. We are checking this request; no new generation has been submitted.',
      );
      timer = Timer(const Duration(seconds: 5), poll);
    }
  }

  Future<void> refreshLimits() async {
    try {
      final value = await widget.repository.availability();
      if (mounted) setState(() => limits = value);
    } catch (_) {
      /* Displayed limits are advisory; the backend always enforces admission. */
    }
  }

  Future<void> moreGarments() async {
    if (nextPage == null || locked) return;
    setState(() => busy = true);
    try {
      final page = await widget.repository.list(pageToken: nextPage);
      if (mounted)
        setState(() {
          for (final item in page.items) {
            if (tryOnCategories.contains(item.category) &&
                !garments.any((g) => g.id == item.id))
              garments.add(item);
          }
          nextPage = page.nextPageToken;
        });
    } catch (e) {
      if (mounted) setState(() => error = fashionError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addPhoto() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final photo = await chooseReferencePhoto(
        context,
        widget.repository,
        pickPhoto: widget.pickReferencePhoto,
        onUpload: () {
          if (mounted) setState(() => uploading = true);
        },
      );
      if (photo != null && mounted)
        setState(() {
          photos.insert(0, photo);
          referenceId = photo.id;
          consent = false;
          requestId = null;
        });
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

  Future<void> generate() async {
    if (garmentId == null || referenceId == null) return;
    if (!uncertain && !consent) return;
    final id = requestId ??= TryOnRepository.newJobId();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final job = await widget.repository.createJob(
        id: id,
        garmentId: garmentId!,
        referenceId: referenceId!,
      );
      if (!mounted) return;
      apply(job);
      setState(() => consent = false);
      await refreshLimits();
    } catch (e) {
      // Retain the same ID/selection after an ambiguous network failure. The
      // explicit check button safely replays it without another reservation.
      if (mounted)
        setState(() {
          error = fashionError(e);
          uncertain =
              !(e is WardrobeFailure &&
                  e.status != null &&
                  e.status! >= 400 &&
                  e.status! < 500);
          if (!uncertain) requestId = null;
        });
      await refreshLimits();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel() async {
    if (current == null) return;
    setState(() {
      cancelling = true;
      error = null;
    });
    try {
      final value = await widget.repository.cancel(current!.id);
      if (mounted) apply(value);
      await refreshLimits();
    } catch (e) {
      if (mounted) setState(() => error = fashionError(e));
    } finally {
      if (mounted) setState(() => cancelling = false);
    }
  }

  void reset() {
    timer?.cancel();
    setState(() {
      current = null;
      requestId = null;
      uncertain = false;
      consent = false;
      error = pollError = null;
    });
  }

  Widget selector({required bool person}) {
    final selected = person ? referenceId : garmentId;
    final choices = person
        ? photos
              .map(
                (p) => DropdownMenuItem(
                  value: p.id,
                  child: Text(photoDate(p.createdAt)),
                ),
              )
              .toList()
        : garments
              .map(
                (g) => DropdownMenuItem(
                  value: g.id,
                  child: Text(g.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              person ? 'Your reference photo' : 'From your wardrobe',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (selected != null)
              SizedBox(
                height: 220,
                child: PrivatePhoto(
                  identity: '${person ? 'person' : 'garment'}-$selected',
                  load: () => person
                      ? widget.repository.referenceImage(selected)
                      : widget.repository.image(selected),
                ),
              ),
            if (choices.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey('selection-$person-$selected'),
                initialValue: selected,
                isExpanded: true,
                items: choices,
                decoration: InputDecoration(
                  labelText: person ? 'Choose photo' : 'Choose garment',
                ),
                onChanged: locked || loading
                    ? null
                    : (value) => setState(() {
                        if (person)
                          referenceId = value;
                        else
                          garmentId = value;
                        consent = false;
                        requestId = null;
                      }),
              ),
            if (person)
              TextButton.icon(
                key: const Key('tryon-add-photo'),
                onPressed: locked || loading ? null : addPhoto,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(uploading ? 'Uploading…' : 'Add reference photo'),
              ),
            if (!person && garments.isEmpty)
              TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, '/wardrobe').then((_) {
                      if (mounted) load();
                    }),
                child: const Text('Add a wardrobe garment'),
              ),
            if (!person && nextPage != null)
              TextButton(
                onPressed: locked ? null : moreGarments,
                child: const Text('Load more garments'),
              ),
          ],
        ),
      ),
    );
  }

  Widget jobState(TryOnJob job) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (job.active) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              job.state == TryOnState.queued
                  ? 'Your preview is queued'
                  : 'Creating your try-on preview',
              key: const Key('tryon-progress'),
            ),
            const SizedBox(height: 12),
            const Text(
              'You can leave this screen and check back. Cancelling a request that has started still uses your generation allowance.',
            ),
            TextButton(
              key: const Key('tryon-cancel'),
              onPressed: cancelling ? null : cancel,
              child: Text(cancelling ? 'Cancelling…' : 'Cancel generation'),
            ),
          ],
          if (job.state == TryOnState.failed) ...[
            Text(job.failureMessage, key: const Key('tryon-failed')),
            const SizedBox(height: 12),
            const Text(
              'This request will not be retried automatically. Failed attempts can still count toward your limit.',
            ),
          ],
          if (job.state == TryOnState.cancelled)
            const Text('Generation cancelled', key: Key('tryon-cancelled')),
          if (job.state == TryOnState.succeeded && !job.expired) ...[
            const Text('Your AI-generated preview', key: Key('tryon-success')),
            const SizedBox(height: 16),
            ExpansionTile(
              key: const Key('tryon-compare-original'),
              title: const Text('Compare original garment'),
              subtitle: const Text('Check the hem and sleeve lengths'),
              children: [
                SizedBox(
                  height: 240,
                  child: PrivatePhoto(
                    identity: 'original-${job.garmentId}',
                    load: () => widget.repository.image(job.garmentId),
                  ),
                ),
              ],
            ),
            AspectRatio(
              aspectRatio: 0.8,
              child: PrivatePhoto(
                identity: 'preview-${job.id}',
                load: () => widget.repository.preview(job.id),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'A visual suggestion, not a fit or sizing guarantee. Your preview expires with its reference photo.',
            ),
            SaveLookButton(
              key: ValueKey('save-${job.id}'),
              jobId: job.id,
              repository: widget.repository,
            ),
            LookExportActions(
              key: ValueKey('export-${job.id}'),
              load: () => widget.repository.preview(job.id),
            ),
          ],
          if (job.expired)
            const Text(
              'This preview has expired. Choose a new reference photo.',
            ),
          if (!job.active)
            TextButton(
              key: const Key('tryon-reset'),
              onPressed: reset,
              child: const Text('Start another try-on'),
            ),
          if (pollError != null) Text(pollError!),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Try on'),
      actions: [
        IconButton(
          tooltip: 'Refresh try-on',
          onPressed: busy || cancelling ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'See it on you',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'Pair a private reference photo with a saved garment. Vyoora creates one AI preview when you choose Generate.',
            ),
            const SizedBox(height: 16),
            if (loading || uploading) const LinearProgressIndicator(),
            if (error != null && current != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(error!, key: const Key('tryon-error')),
              ),
            if (current != null) jobState(current!),
            if (current == null) ...[
              LayoutBuilder(
                builder: (context, size) => size.maxWidth >= 650
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: selector(person: true)),
                          Expanded(child: selector(person: false)),
                        ],
                      )
                    : Column(
                        children: [
                          selector(person: true),
                          selector(person: false),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              if (limits != null)
                Text(
                  limits!.enabled
                      ? '${limits!.remainingToday} of ${limits!.dailyLimit} generations remaining today. Daily limits reset at 00:00 UTC.'
                      : 'Try-on generation is paused or not enabled for this test account.',
                ),
              CheckboxListTile(
                key: const Key('tryon-generation-consent'),
                contentPadding: EdgeInsets.zero,
                value: consent,
                onChanged: locked || loading
                    ? null
                    : (value) => setState(() => consent = value!),
                title: const Text(
                  'Send these selected photos to Google Vertex AI to generate this private preview.',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(error!, key: const Key('tryon-error')),
                ),
              if (uncertain)
                const Text(
                  'The request may already be running. Check this same request before starting another.',
                ),
              FilledButton.icon(
                key: const Key('tryon-generate'),
                onPressed:
                    busy ||
                        loading ||
                        garmentId == null ||
                        referenceId == null ||
                        (!uncertain &&
                            (!consent ||
                                limits?.enabled != true ||
                                (limits?.remainingToday ?? 0) <= 0))
                    ? null
                    : generate,
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  busy
                      ? 'Submitting…'
                      : uncertain
                      ? 'Check this request'
                      : 'Generate preview',
                ),
              ),
            ],
            const SizedBox(height: 24),
            TextButton(
              onPressed: () =>
                  Navigator.pushNamed(
                    context,
                    '/fashion/reference-photos',
                  ).then((_) {
                    if (mounted) load();
                  }),
              child: const Text('Manage reference photos and consent'),
            ),
          ],
        ),
      ),
    ),
  );
}
