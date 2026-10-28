import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyoora/navigation/fashion_routes.dart';
import 'package:vyoora/screens/home_shell.dart';

void main() {
  Future<void> openShell(WidgetTester tester, {double width = 390}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        routes: fashionRoutes,
        home: const HomeShell(
          primaryScreens: [
            Text('Existing scan screen'),
            Text('Existing history screen'),
            Text('Existing chat screen'),
            Text('Existing profile screen'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Fashion opens Wardrobe and back retains the selected Fashion tab',
    (tester) async {
      await openShell(tester);
      await tester.tap(find.byKey(const Key('nav-fashion')));
      await tester.pumpAndSettle();
      expect(find.text('Make room for your style'), findsOneWidget);
      await tester.tap(find.text('Wardrobe'));
      await tester.pumpAndSettle();
      expect(find.text('Your wardrobe starts here'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Make room for your style'), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
    },
  );
  testWidgets(
    'Reference photos and saved looks have working routes and back paths',
    (tester) async {
      await openShell(tester);
      await tester.tap(find.byKey(const Key('nav-fashion')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reference photos'));
      await tester.pumpAndSettle();
      expect(find.text('Open wardrobe'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Saved looks'));
      await tester.tap(find.text('Saved looks'));
      await tester.pumpAndSettle();
      expect(find.text('No saved looks yet'), findsOneWidget);
      await tester.tap(find.text('Explore wardrobe'));
      await tester.pumpAndSettle();
      expect(find.text('Your wardrobe starts here'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('No saved looks yet'), findsOneWidget);
    },
  );
  testWidgets(
    'all existing destinations remain reachable at a narrow phone width',
    (tester) async {
      await openShell(tester, width: 320);
      for (final item in {
        'nav-history': 'Existing history screen',
        'nav-chat': 'Existing chat screen',
        'nav-profile': 'Existing profile screen',
        'nav-home': 'Existing scan screen',
      }.entries) {
        await tester.tap(find.byKey(Key(item.key)));
        await tester.pumpAndSettle();
        expect(find.text(item.value), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
