import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:vyoora/models/fashion/domain.dart';
import 'package:vyoora/screens/fashion/wardrobe_screen.dart';
import 'package:vyoora/services/wardrobe_repository.dart';
import 'package:vyoora/services/wardrobe_session.dart';

class TestSession extends WardrobeSession {
  TestSession() : super(apiKey: 'public-config', project: 'demo-test') {
    uid = 'alice';
    email = 'alice@example.invalid';
  }
  @override
  Future<String> token({bool forceRefresh = false}) async => 'test-session';
}

void main() {
  final date = DateTime.utc(2026, 10, 28);
  WardrobeItem garment(String id, {String owner = 'alice'}) => WardrobeItem(
    id: id,
    ownerId: owner,
    name: 'Blue shirt',
    category: GarmentCategory.top,
    image: PrivateImageRef(
      ownerId: owner,
      imageId: id,
      kind: ImageKind.wardrobe,
    ),
    createdAt: date,
    updatedAt: date,
  );

  test('Firebase login refresh and sign-out; no password stored', () async {
    var refreshes = 0;
    final session = WardrobeSession(
      apiKey: 'public-config',
      project: 'test',
      client: MockClient((request) async {
        if (request.url.host == 'securetoken.googleapis.com') {
          refreshes++;
          expect(request.body, contains('grant_type=refresh_token'));
          return http.Response(
            jsonEncode({
              'id_token': 'new-token',
              'refresh_token': 'refresh-2',
              'expires_in': '3600',
            }),
            200,
          );
        }
        expect(request.url.path, '/v1/accounts:signInWithPassword');
        return http.Response(
          jsonEncode({
            'localId': 'alice',
            'email': 'alice@example.invalid',
            'idToken': 'initial',
            'refreshToken': 'refresh',
            'expiresIn': '3600',
          }),
          200,
        );
      }),
    );
    await session.signIn('alice@example.invalid', 'example-password');
    expect(await session.token(), 'initial');
    expect(await session.token(forceRefresh: true), 'new-token');
    expect(refreshes, 1);
    session.signOut();
    expect(session.uid, isNull);
    await expectLater(session.token(), throwsA(isA<WardrobeFailure>()));
  });

  test('repository rejects records owned by another account', () async {
    final session = TestSession();
    final repository = WardrobeRepository(
      session: session,
      base: 'https://wardrobe.example.invalid',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-session');
        return http.Response(
          jsonEncode({
            'items': [garment('shirt', owner: 'bob').toJson()],
            'nextPageToken': null,
          }),
          200,
        );
      }),
    );
    await expectLater(repository.list(), throwsA(isA<WardrobeFailure>()));
  });

  test(
    'API failure cannot become an uploaded garment or successful deletion',
    () async {
      final repository = WardrobeRepository(
        session: TestSession(),
        base: 'https://wardrobe.example.invalid',
        client: MockClient(
          (_) async => http.Response('{"code":"storage_unavailable"}', 503),
        ),
      );
      await expectLater(
        repository.upload(
          bytes: Uint8List.fromList([1]),
          name: 'Shirt',
          category: GarmentCategory.top,
        ),
        throwsA(isA<WardrobeFailure>()),
      );
      await expectLater(
        repository.delete('shirt'),
        throwsA(isA<WardrobeFailure>()),
      );
    },
  );

  testWidgets(
    'upload populates grid; failed delete preserves card; retry deletes; sign-out clears',
    (tester) async {
      final session = TestSession();
      final records = <WardrobeItem>[];
      var deleteFails = true;
      final photo = Uint8List.fromList(
        img.encodePng(img.Image(width: 16, height: 16)),
      );
      final repository = WardrobeRepository(
        session: session,
        base: 'https://wardrobe.example.invalid',
        client: MockClient((request) async {
          if (request.method == 'POST') {
            expect(
              request.headers['content-type'],
              startsWith('multipart/form-data'),
            );
            records.add(garment('shirt'));
            return http.Response(
              jsonEncode({'item': records.single.toJson()}),
              201,
            );
          }
          if (request.method == 'DELETE') {
            if (deleteFails)
              return http.Response('{"code":"storage_unavailable"}', 503);
            records.clear();
            return http.Response('', 204);
          }
          if (request.url.path.endsWith('/image'))
            return http.Response.bytes(photo, 200);
          return http.Response(
            jsonEncode({
              'items': records.map((item) => item.toJson()).toList(),
              'nextPageToken': null,
            }),
            200,
          );
        }),
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: WardrobeScreen(
            session: session,
            repository: repository,
            pickPhoto: () async => photo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No garments yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('add-garment')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('garment-name')),
        'Blue shirt',
      );
      await tester.tap(find.byKey(const Key('garment-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-garment')));
      await tester.pumpAndSettle();
      expect(find.text('Blue shirt'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.byTooltip('Delete Blue shirt'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Blue shirt'), findsOneWidget);
      expect(find.byKey(const Key('wardrobe-error')), findsOneWidget);
      deleteFails = false;
      await tester.tap(find.byTooltip('Delete Blue shirt'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await tester.pumpAndSettle();
      expect(find.text('No garments yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('wardrobe-sign-out')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wardrobe-email')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
