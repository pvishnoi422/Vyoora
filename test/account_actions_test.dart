import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyoora/screens/fashion/account_actions.dart';
import 'package:vyoora/services/wardrobe_repository.dart';
import 'package:vyoora/services/wardrobe_session.dart';
import 'tryon_test.dart' show Session;

class AccountRepo extends WardrobeRepository {
  int calls = 0;
  AccountRepo()
    : super(session: Session(), base: 'https://test.example.invalid');
  @override
  Future<void> deleteAccount(String password) async {
    calls++;
    if (password != 'synthetic-password') throw const WardrobeFailure('Denied');
    session.signOut();
  }
}

void main() {
  testWidgets(
    'account deletion needs confirmation and password; failure remains retryable',
    (tester) async {
      final repo = AccountRepo();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AccountActions(repository: repo)),
        ),
      );
      await tester.tap(find.byKey(const Key('account-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep account'));
      await tester.pumpAndSettle();
      expect(repo.calls, 0);
      expect(repo.session.signedIn, isTrue);
      Future<void> confirm(String password) async {
        await tester.tap(find.byKey(const Key('account-delete')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('account-delete-password')),
          password,
        );
        await tester.tap(find.byKey(const Key('account-confirm-delete')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
      }

      await confirm('wrong');
      expect(repo.calls, 1);
      expect(repo.session.signedIn, isTrue);
      expect(
        find.textContaining('Could not finish account deletion'),
        findsOneWidget,
      );
      await confirm('synthetic-password');
      expect(repo.calls, 2);
      expect(repo.session.signedIn, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
