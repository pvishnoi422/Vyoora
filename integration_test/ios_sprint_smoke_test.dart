import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:vyoora/services/look_export.dart';
import 'package:vyoora/services/wardrobe_session.dart';
import 'package:vyoora/services/tryon_repository.dart';
import 'package:vyoora/screens/fashion/saved_looks_screen.dart';
import 'wardrobe_smoke_test.dart' as wardrobe;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const denied = bool.fromEnvironment('TEST_PHOTOS_DENIED');
  const exportsOnly = bool.fromEnvironment('TEST_EXPORTS_ONLY');
  if (!denied && !exportsOnly) wardrobe.main();
  testWidgets(
    denied
        ? 'iOS denied Photos permission is reported'
        : 'iOS export pixels, Photos asset and native share sheet',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Vyoora export verification')),
        ),
      );
      await tester.pumpAndSettle();
      final source = img.Image(width: 800, height: 1200)
        ..clear(img.ColorRgb8(30, 60, 90));
      final bytes = Uint8List.fromList(img.encodePng(source));
      final original = List<int>.of(bytes);
      final exporter = LookExport();
    Future<void> rememberAsset(String? id) async {
      expect(id, isNotEmpty);
      // QA-only IDs let the host verify Photos after Flutter removes the app sandbox.
      debugPrint('VYOORA_NATIVE_PHOTO_ASSET_ID=$id');
    }
      if (denied) {
        await expectLater(
          exporter.save(bytes),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'permission code',
              'permission_denied',
            ),
          ),
        );
        return;
      }
      final encoded = await LookExport.channel.invokeMethod<Uint8List>(
        'testWatermark',
        bytes,
      );
      final output = img.decodePng(encoded!)!;
      expect(output.width, source.width);
      expect(output.height, source.height);
      expect(bytes, orderedEquals(original));
      expect(output.getPixel(100, 100).r, source.getPixel(100, 100).r);
      var changed = 0;
      for (var y = 1100; y < 1200; y++) {
        for (var x = 300; x < 800; x++) {
          if (output.getPixel(x, y).r != source.getPixel(x, y).r) changed++;
        }
      }
      expect(changed, greaterThan(100));
    debugPrint('VYOORA_NATIVE_WATERMARK_VERIFIED');
      final asset = await exporter.save(bytes);
    await rememberAsset(asset);
    // The host verifies these exact IDs in the disposable simulator's Photos
    // library. The app correctly has add-only permission, not read permission.
    debugPrint('VYOORA_NATIVE_PHOTOS_SAVE_COMPLETED');
      // Open the real share sheet, then cancel without sending to another app.
      final sharing = exporter.share(bytes);
      var presented = false;
      for (var n = 0; n < 20 && !presented; n++) {
        await tester.pump(const Duration(milliseconds: 250));
        presented =
            await LookExport.channel.invokeMethod<bool>('testSharePresented') ??
            false;
      }
      expect(presented, isTrue);
    debugPrint('VYOORA_NATIVE_SHARE_SHEET_VERIFIED');
      await LookExport.channel.invokeMethod<void>('testDismissShare');
      expect(await sharing.timeout(const Duration(seconds: 10)), isFalse);
      expect(tester.takeException(), isNull);
      const email = String.fromEnvironment('TEST_LOOK_EMAIL');
      const lookId = String.fromEnvironment('TEST_LOOK_ID');
      if (email.isNotEmpty && lookId.isNotEmpty) {
        final session = WardrobeSession();
        await session.signIn(email, 'Vyoora-local-only-2026!');
        final repository = TryOnRepository(session: session);
        final page = await repository.looks();
        expect(page.items.any((look) => look.id == lookId), isTrue);
        final actual = await repository.lookImage(lookId);
        final savedAsset = await exporter.save(actual);
      await rememberAsset(savedAsset);
        // Reopen persisted data in a new widget, then delete through the real UI.
        await tester.pumpWidget(
          MaterialApp(
            home: SavedLooksScreen(session: session, repository: repository),
          ),
        );
        Future<void> waitFor(Finder finder) async {
          final end = DateTime.now().add(const Duration(seconds: 60));
          while (finder.evaluate().isEmpty && DateTime.now().isBefore(end)) {
            await tester.pump(const Duration(milliseconds: 250));
          }
          expect(finder, findsWidgets);
        }

        await waitFor(find.byKey(ValueKey('look-$lookId')));
        await tester.tap(find.byKey(ValueKey('look-$lookId')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('look-delete')),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.byKey(const Key('look-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('look-confirm-delete')));
        await waitFor(find.text('No saved looks yet'));
        expect((await repository.looks()).items, isEmpty);
        session.signOut();
      }
    },
  );
}
