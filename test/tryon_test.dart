import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:vyoora/models/fashion/domain.dart';
import 'package:vyoora/models/fashion/tryon_job.dart';
import 'package:vyoora/screens/fashion/tryon_screen.dart';
import 'package:vyoora/screens/fashion/reference_photos_screen.dart';
import 'package:vyoora/services/tryon_repository.dart';
import 'package:vyoora/services/wardrobe_repository.dart';
import 'package:vyoora/services/wardrobe_session.dart';

class Session extends WardrobeSession {
  Session() : super(apiKey: 'synthetic', project: 'demo-test') {
    uid = 'alice';
    email = 'alice@example.invalid';
  }
  @override
  Future<String> token({bool forceRefresh = false}) async => 'synthetic';
}

class Repo extends TryOnRepository {
  final now = DateTime.now().toUtc();
  late final bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 32, height: 48)),
  );
  List<ReferencePhoto> photos = [];
  final ids = <String>[];
  TryOnJob? current;
  TryOnAvailability availabilityValue = const TryOnAvailability(true, 3, 3);
  bool loseResponse = false, quotaRejected = false;
  int uploads = 0, cancels = 0;
  Completer<TryOnJob>? pendingPoll;
  Repo() : super(session: Session(), base: 'https://tryon.example.invalid');
  ReferencePhoto photo() => ReferencePhoto(
    id: 'person',
    ownerId: 'alice',
    createdAt: now,
    consentedAt: now,
    expiresAt: now.add(const Duration(days: 7)),
    image: PrivateImageRef(
      ownerId: 'alice',
      imageId: 'person',
      kind: ImageKind.referencePhoto,
      expiresAt: now.add(const Duration(days: 7)),
    ),
  );
  TryOnJob state(TryOnState status, {String? error}) => TryOnJob(
    id: current?.id ?? 'generation',
    ownerId: 'alice',
    garmentId: 'shirt',
    referenceId: 'person',
    state: status,
    createdAt: now,
    expiresAt: now.add(const Duration(days: 7)),
    errorCode: error,
  );
  @override
  Future<WardrobePage> list({String? pageToken}) async => WardrobePage([
    WardrobeItem(
      id: 'shirt',
      ownerId: 'alice',
      name: 'Navy sweater',
      category: GarmentCategory.top,
      createdAt: now,
      updatedAt: now,
      image: PrivateImageRef(
        ownerId: 'alice',
        imageId: 'shirt',
        kind: ImageKind.wardrobe,
      ),
    ),
  ], null);
  @override
  Future<List<ReferencePhoto>> references() async => List.of(photos);
  @override
  Future<TryOnAvailability> availability() async => availabilityValue;
  @override
  Future<List<TryOnJob>> jobs() async => current == null ? [] : [current!];
  @override
  Future<Uint8List> image(String id) async => bytes;
  @override
  Future<Uint8List> referenceImage(String id) async => bytes;
  @override
  Future<Uint8List> preview(String id) async => bytes;
  @override
  Future<ReferencePhoto> uploadReference(Uint8List bytes) async {
    uploads++;
    final value = photo();
    photos = [value];
    return value;
  }

  @override
  Future<TryOnJob> createJob({
    required String id,
    required String garmentId,
    required String referenceId,
  }) async {
    ids.add(id);
    if (quotaRejected) {
      availabilityValue = const TryOnAvailability(true, 0, 3);
      throw const WardrobeFailure(
        'Your daily try-on limit has been reached.',
        code: 'tryon_quota_exhausted',
        status: 429,
      );
    }
    current = TryOnJob(
      id: id,
      ownerId: 'alice',
      garmentId: garmentId,
      referenceId: referenceId,
      state: TryOnState.queued,
      createdAt: now,
      expiresAt: now.add(const Duration(days: 7)),
    );
    if (loseResponse) {
      loseResponse = false;
      throw TimeoutException('synthetic lost response');
    }
    return current!;
  }

  @override
  Future<TryOnJob> job(String id) async =>
      pendingPoll == null ? current! : pendingPoll!.future;
  @override
  Future<TryOnJob> cancel(String id) async {
    cancels++;
    current = state(TryOnState.cancelled);
    return current!;
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    Repo repo, {
    bool referencePage = false,
    String? initialReferenceId,
  }) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: referencePage
            ? ReferencePhotosScreen(
                session: repo.session,
                repository: repo,
                pickPhoto: () async => repo.bytes,
              )
            : TryOnScreen(
                session: repo.session,
                repository: repo,
                initialGarmentId: 'shirt',
                initialReferenceId: initialReferenceId,
                pickReferencePhoto: () async => repo.bytes,
              ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Key key) async {
    if (find.byKey(key).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.byKey(key),
        250,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
    }
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
  }

  Future<void> generate(WidgetTester tester) async {
    await reveal(tester, const Key('tryon-generation-consent'));
    await tester.tap(find.byKey(const Key('tryon-generation-consent')));
    await tester.pump();
    await reveal(tester, const Key('tryon-generate'));
    await tester.tap(find.byKey(const Key('tryon-generate')));
    await tester.pump();
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  test('unverified success and unknown job states are rejected', () {
    final now = DateTime.now().toUtc();
    final json = {
      'id': 'job',
      'ownerId': 'alice',
      'garmentId': 'shirt',
      'referenceId': 'person',
      'status': 'succeeded',
      'createdAt': now.toIso8601String(),
      'expiresAt': now.add(const Duration(days: 7)).toIso8601String(),
    };
    expect(() => TryOnJob.fromJson(json), throwsFormatException);
    expect(
      () => TryOnJob.fromJson({...json, 'status': 'unexpected'}),
      throwsFormatException,
    );
    expect(
      TryOnJob.fromJson({...json, 'aiGenerated': true}).state,
      TryOnState.succeeded,
    );
  });
  test('try-on repository rejects cross-account job responses', () async {
    final session = Session();
    final now = DateTime.now().toUtc();
    final repo = TryOnRepository(
      session: session,
      base: 'https://tryon.example.invalid',
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'job': {
              'id': 'job',
              'ownerId': 'bob',
              'garmentId': 'shirt',
              'referenceId': 'person',
              'status': 'queued',
              'createdAt': now.toIso8601String(),
              'expiresAt': now.add(const Duration(days: 7)).toIso8601String(),
            },
          }),
          200,
        ),
      ),
    );
    await expectLater(repo.job('job'), throwsA(isA<WardrobeFailure>()));
  });
  testWidgets(
    'both reference consent checks required; cancel sends nothing; upload persists a card',
    (tester) async {
      final repo = Repo();
      await mount(tester, repo, referencePage: true);
      await tester.tap(find.byKey(const Key('add-reference-photo')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('reference-upload-consented')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byKey(const Key('reference-permission')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reference-permission')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('reference-upload-consented')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.uploads, 0);
      await tester.tap(find.byKey(const Key('add-reference-photo')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('reference-permission')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reference-permission')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('reference-processing')));
      await tester.tap(find.byKey(const Key('reference-processing')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reference-upload-consented')));
      await tester.pumpAndSettle();
      expect(repo.uploads, 1);
      expect(find.text('No reference photos yet.'), findsNothing);
      expect(find.text('Delete photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await dispose(tester);
    },
  );
  testWidgets(
    'saved garment selection needs per-generation consent; queued -> running -> successful preview',
    (tester) async {
      final repo = Repo();
      repo.photos = [repo.photo()];
      await mount(tester, repo);
      await reveal(tester, const Key('tryon-generate'));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('tryon-generate')))
            .onPressed,
        isNull,
      );
      await generate(tester);
      expect(repo.ids.length, 1);
      expect(find.byKey(const Key('tryon-progress')), findsOneWidget);
      repo.current = repo.state(TryOnState.running);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Creating your try-on preview'), findsOneWidget);
      repo.current = repo.state(TryOnState.succeeded);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tryon-success')), findsOneWidget);
      expect(find.byKey(const Key('tryon-cancel')), findsNothing);
      expect(tester.takeException(), isNull);
      await dispose(tester);
    },
  );
  testWidgets(
    'ambiguous submission reuses the same ID instead of creating another generation',
    (tester) async {
      final repo = Repo();
      repo.photos = [repo.photo()];
      repo.loseResponse = true;
      await mount(tester, repo);
      await generate(tester);
      await tester.pumpAndSettle();
      await reveal(tester, const Key('tryon-generate'));
      expect(find.text('Check this request'), findsOneWidget);
      await reveal(tester, const Key('tryon-generate'));
      await tester.tap(find.byKey(const Key('tryon-generate')));
      await tester.pump();
      await tester.pump();
      expect(repo.ids.length, 2);
      expect(repo.ids.toSet().length, 1);
      await reveal(tester, const Key('tryon-cancel'));
      await tester.tap(find.byKey(const Key('tryon-cancel')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('tryon-cancelled')), findsOneWidget);
      await dispose(tester);
    },
  );
  testWidgets('late running poll cannot reverse acknowledged cancellation', (
    tester,
  ) async {
    final repo = Repo();
    repo.photos = [repo.photo()];
    await mount(tester, repo);
    await generate(tester);
    repo.pendingPoll = Completer<TryOnJob>();
    await tester.pump(const Duration(seconds: 2));
    await reveal(tester, const Key('tryon-cancel'));
    await tester.tap(find.byKey(const Key('tryon-cancel')));
    await tester.pump();
    await tester.pump();
    repo.pendingPoll!.complete(repo.state(TryOnState.running));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('tryon-cancelled')), findsOneWidget);
    expect(find.byKey(const Key('tryon-success')), findsNothing);
    await dispose(tester);
  });
  testWidgets(
    'generation failure is visible and never displayed as a preview',
    (tester) async {
      final repo = Repo();
      repo.photos = [repo.photo()];
      await mount(tester, repo);
      await generate(tester);
      repo.current = repo.state(TryOnState.failed, error: 'generation_blocked');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byKey(const Key('tryon-failed')), findsOneWidget);
      expect(find.byKey(const Key('tryon-success')), findsNothing);
      expect(repo.ids.length, 1);
      await dispose(tester);
    },
  );
  testWidgets(
    'known quota refusal unlocks selection and disables a new generation',
    (tester) async {
      final repo = Repo();
      repo.photos = [repo.photo()];
      repo.quotaRejected = true;
      await mount(tester, repo);
      await generate(tester);
      await tester.pumpAndSettle();
      await reveal(tester, const Key('tryon-error'));
      expect(find.text('Check this request'), findsNothing);
      expect(
        find.text('Your daily try-on limit has been reached.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('tryon-generate')))
            .onPressed,
        isNull,
      );
      await dispose(tester);
    },
  );
  testWidgets(
    'wardrobe selection opens a new form instead of an unrelated previous result',
    (tester) async {
      final repo = Repo();
      repo.photos = [repo.photo()];
      repo.current = repo.state(TryOnState.succeeded);
      await mount(tester, repo);
      await reveal(tester, const Key('tryon-generate'));
      expect(find.byKey(const Key('tryon-success')), findsNothing);
      expect(repo.ids, isEmpty);
      await dispose(tester);
    },
  );
  testWidgets(
    'a selected reference photo is retained instead of replaced with the newest one',
    (tester) async {
      final repo = Repo();
      final created = repo.now.subtract(const Duration(days: 1));
      final expiry = created.add(const Duration(days: 7));
      repo.photos = [
        repo.photo(),
        ReferencePhoto(
          id: 'older',
          ownerId: 'alice',
          createdAt: created,
          consentedAt: created,
          expiresAt: expiry,
          image: PrivateImageRef(
            ownerId: 'alice',
            imageId: 'older',
            kind: ImageKind.referencePhoto,
            expiresAt: expiry,
          ),
        ),
      ];
      await mount(tester, repo, initialReferenceId: 'older');
      expect(
        find.byKey(const ValueKey('selection-true-older')),
        findsOneWidget,
      );
      await dispose(tester);
    },
  );
}
