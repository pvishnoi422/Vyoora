import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyoora/models/fashion/domain.dart';
import 'package:vyoora/screens/fashion/saved_looks_screen.dart';
import 'package:vyoora/screens/fashion/look_actions.dart';
import 'package:vyoora/services/look_export.dart';
import 'package:vyoora/services/tryon_repository.dart';
import 'tryon_test.dart' show Session;
import 'package:image/image.dart' as img;

class LooksRepo extends TryOnRepository {
  final now = DateTime.now().toUtc();
  final records = <SavedLook>[];
  int deletes = 0;
  LooksRepo() : super(session: Session(), base: 'https://test.example.invalid');
  @override
  Future<SavedLooksPage> looks({String? pageToken}) async =>
      SavedLooksPage(List.of(records), null);
  @override
  Future<Uint8List> lookImage(String id) async =>
      Uint8List.fromList(img.encodePng(img.Image(width: 32, height: 48)));
  @override
  Future<SavedLook> saveLook(String jobId, String title) async {
    final look = SavedLook(
      id: jobId,
      ownerId: 'alice',
      title: title,
      items: [OwnedItemId(ownerId: 'alice', id: 'shirt')],
      state: LookState.saved,
      preview: PrivateImageRef(
        ownerId: 'alice',
        imageId: jobId,
        kind: ImageKind.savedLook,
        expiresAt: now.add(const Duration(days: 30)),
      ),
      createdAt: now,
      updatedAt: now,
    );
    records.add(look);
    return look;
  }

  @override
  Future<void> deleteLook(String id) async {
    deletes++;
    records.removeWhere((r) => r.id == id);
  }
}

class Exporter extends LookExport {
  bool denied = false;
  int saves = 0, shares = 0;
  @override
  bool get supported => true;
  @override
  Future<String?> save(Uint8List bytes) async {
    if (denied) throw PlatformException(code: 'permission_denied');
    saves++;
    return 'asset';
  }

  @override
  Future<bool> share(Uint8List bytes) async {
    shares++;
    return false;
  }
}

void main() {
  testWidgets(
    'save consent, reopen My Looks after widget restart, delete and isolate sign-out',
    (tester) async {
      final repo = LooksRepo();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SaveLookButton(jobId: 'job', repository: repo),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('look-save')));
      await tester.pumpAndSettle();
      expect(repo.records, isEmpty);
      await tester.tap(find.byKey(const Key('look-confirm-save')));
      await tester.pumpAndSettle();
      expect(repo.records.length, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.pumpWidget(
        MaterialApp(
          home: SavedLooksScreen(session: repo.session, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('My look'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('look-job')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('look-delete')),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('look-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('look-confirm-delete')));
      await tester.pumpAndSettle();
      expect(repo.deletes, 1);
      expect(find.text('No saved looks yet'), findsOneWidget);
      repo.session.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Open wardrobe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Photos permission denial is actionable and cancelled sharing is not success',
    (tester) async {
      final exporter = Exporter()..denied = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LookExportActions(
              exporter: exporter,
              load: () async => Uint8List(4),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('look-save-photos')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Photos access is off'), findsOneWidget);
      expect(exporter.saves, 0);
      exporter.denied = false;
      await tester.tap(find.byKey(const Key('look-save-photos')));
      await tester.pumpAndSettle();
      expect(find.text('Saved to Photos'), findsOneWidget);
      expect(exporter.saves, 1);
      await tester.tap(find.byKey(const Key('look-share')));
      await tester.pumpAndSettle();
      expect(find.text('Sharing cancelled'), findsOneWidget);
      expect(exporter.shares, 1);
    },
  );
}
