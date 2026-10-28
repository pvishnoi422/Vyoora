import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyoora/models/fashion/domain.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27, 12);
  WardrobeItem garment({String owner = 'alice'}) => WardrobeItem(
    id: 'shirt-1',
    ownerId: owner,
    name: 'Linen shirt',
    category: GarmentCategory.top,
    image: PrivateImageRef(
      ownerId: owner,
      imageId: 'shirt-photo',
      kind: ImageKind.wardrobe,
    ),
    createdAt: now,
    updatedAt: now,
  );
  ReferencePhoto reference() => ReferencePhoto(
    id: 'ref-1',
    ownerId: 'alice',
    image: PrivateImageRef(
      ownerId: 'alice',
      imageId: 'ref-1',
      kind: ImageKind.referencePhoto,
      expiresAt: now.add(const Duration(days: 7)),
    ),
    createdAt: now,
    consentedAt: now,
    expiresAt: now.add(const Duration(days: 7)),
  );

  test(
    'wardrobe item preserves ownership, attributes and private reference through JSON',
    () {
      final item = garment();
      final restored = WardrobeItem.fromJson(
        jsonDecode(jsonEncode(item.toJson())),
      );
      expect(restored.toJson(), item.toJson());
      expect(restored.image!.objectKey, 'wardrobe/alice/shirt-photo.jpg');
      expect(jsonEncode(item.toJson()), isNot(contains('https://')));
    },
  );
  test(
    'reference photo preserves consent and enforces expiry at the boundary',
    () {
      final photo = reference();
      expect(
        ReferencePhoto.fromJson(
          jsonDecode(jsonEncode(photo.toJson())),
        ).toJson(),
        photo.toJson(),
      );
      expect(photo.canUse(now), isTrue);
      expect(photo.canUse(now.subtract(const Duration(seconds: 1))), isFalse);
      expect(photo.canUse(photo.expiresAt), isFalse);
      expect(photo.image.isExpired(photo.expiresAt), isTrue);
    },
  );
  test('references cannot carry another user or exceed seven days', () {
    final json = reference().toJson();
    expect(
      () => ReferencePhoto.fromJson({...json, 'ownerId': 'bob'}),
      throwsFormatException,
    );
    expect(
      () => ReferencePhoto.fromJson({
        ...json,
        'expiresAt': now.add(const Duration(days: 8)).toIso8601String(),
      }),
      throwsFormatException,
    );
    expect(
      () => ReferencePhoto.fromJson({
        ...json,
        'consentedAt': now.subtract(const Duration(days: 1)).toIso8601String(),
        'createdAt': now.subtract(const Duration(days: 2)).toIso8601String(),
      }),
      throwsFormatException,
    );
  });
  test(
    'saved looks round-trip relationships and reject cross-user references',
    () {
      final look = SavedLook(
        id: 'look-1',
        ownerId: 'alice',
        title: 'Everyday',
        items: [OwnedItemId(ownerId: 'alice', id: garment().id)],
        referencePhoto: OwnedItemId(ownerId: 'alice', id: reference().id),
        preview: PrivateImageRef(
          ownerId: 'alice',
          imageId: 'look-preview',
          kind: ImageKind.savedLook,
        ),
        state: LookState.saved,
        createdAt: now,
        updatedAt: now,
      );
      expect(
        SavedLook.fromJson(jsonDecode(jsonEncode(look.toJson()))).toJson(),
        look.toJson(),
      );
      expect(
        () => SavedLook.fromJson({
          ...look.toJson(),
          'items': [
            {'ownerId': 'bob', 'id': 'shirt-1'},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => SavedLook.fromJson({...look.toJson(), 'preview': null}),
        throwsFormatException,
      );
      expect(
        () => look.items.add(OwnedItemId(ownerId: 'alice', id: 'x')),
        throwsUnsupportedError,
      );
    },
  );
  test('duplicate or empty look relationships cannot be saved', () {
    expect(
      () => SavedLook(
        id: 'look-1',
        ownerId: 'alice',
        title: 'Look',
        items: [],
        createdAt: now,
        updatedAt: now,
      ),
      throwsFormatException,
    );
    expect(
      () => SavedLook(
        id: 'look-1',
        ownerId: 'alice',
        title: 'Look',
        items: [
          OwnedItemId(ownerId: 'alice', id: 'x'),
          OwnedItemId(ownerId: 'alice', id: 'x'),
        ],
        createdAt: now,
        updatedAt: now,
      ),
      throwsFormatException,
    );
  });
  test(
    'unknown schema, invalid dates, categories and unsafe object IDs are rejected',
    () {
      final json = garment().toJson();
      expect(
        () => WardrobeItem.fromJson({...json, 'schemaVersion': 2}),
        throwsFormatException,
      );
      expect(
        () => WardrobeItem.fromJson({...json, 'createdAt': 'not-a-date'}),
        throwsFormatException,
      );
      expect(
        () => WardrobeItem.fromJson({...json, 'category': 'unknown'}),
        throwsFormatException,
      );
      expect(
        () => WardrobeItem.fromJson({...json, 'id': '../other-user'}),
        throwsFormatException,
      );
      expect(
        () => WardrobeItem.fromJson({...json, 'ownerId': 'bob'}),
        throwsFormatException,
      );
      expect(
        () => WardrobeItem.fromJson({...json, 'name': ''}),
        throwsFormatException,
      );
      expect(
        () => WardrobeItem.fromJson({
          ...json,
          'updatedAt': now
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
        }),
        throwsFormatException,
      );
    },
  );
}
