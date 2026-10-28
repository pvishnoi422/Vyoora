// Runs only against the explicitly configured local demo Auth project/backend.
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:vyoora/screens/fashion/wardrobe_screen.dart';
import 'package:vyoora/services/wardrobe_repository.dart';
import 'package:vyoora/services/wardrobe_session.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('iOS wardrobe upload, reload, account switch, and delete', (
    tester,
  ) async {
    const host = String.fromEnvironment('AUTH_EMULATOR_HOST');
    const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
    if (host != '127.0.0.1:9099' || project != 'demo-vyoora-v2')
      throw StateError('Local demo required');
    final session = WardrobeSession();
    final repository = WardrobeRepository(session: session);
    final photo = Uint8List.fromList(
      img.encodePng(
        img.Image(width: 80, height: 100)..clear(img.ColorRgb8(40, 80, 160)),
      ),
    );
    final name = 'iOS smoke ${DateTime.now().millisecondsSinceEpoch}';
    Future<void> waitFor(Finder finder) async {
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(finder, findsWidgets);
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> signIn(String account) async {
      await waitFor(find.byKey(const Key('wardrobe-email')));
      await tester.enterText(
        find.byKey(const Key('wardrobe-email')),
        '$account@vyoora.example.invalid',
      );
      await tester.enterText(
        find.byKey(const Key('wardrobe-password')),
        'Vyoora-local-only-2026!',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('wardrobe-sign-in')));
      await tester.tap(find.byKey(const Key('wardrobe-sign-in')));
      await waitFor(find.byKey(const Key('add-garment')));
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (find.byType(LinearProgressIndicator).evaluate().isNotEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byKey(const Key('wardrobe-error')), findsNothing);
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: WardrobeScreen(
          session: session,
          repository: repository,
          pickPhoto: () async => photo,
        ),
      ),
    );
    await signIn('alice');
    await tester.tap(find.byKey(const Key('add-garment')));
    await waitFor(find.byKey(const Key('garment-name')));
    await tester.enterText(find.byKey(const Key('garment-name')), name);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.byKey(const Key('garment-consent')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('save-garment')));
    await waitFor(find.text(name));
    await waitFor(find.byType(Image));
    await tester.tap(find.byKey(const Key('wardrobe-refresh')));
    await tester.pump(const Duration(seconds: 2));
    await waitFor(find.text(name));
    await tester.tap(find.byKey(const Key('wardrobe-sign-out')));
    await signIn('bob');
    expect(find.text(name), findsNothing);
    await tester.tap(find.byKey(const Key('wardrobe-sign-out')));
    await signIn('alice');
    await waitFor(find.text(name));
    await tester.tap(find.byTooltip('Delete $name'));
    await waitFor(find.byKey(const Key('confirm-delete')));
    await tester.tap(find.byKey(const Key('confirm-delete')));
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (find.text(name).evaluate().isNotEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text(name), findsNothing);
    await tester.tap(find.byKey(const Key('wardrobe-refresh')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(name), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
