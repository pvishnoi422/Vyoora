/// V2 domain records contain private object references, never public image URLs.
enum ImageKind { wardrobe, referencePhoto, savedLook }

enum GarmentCategory { top, bottom, dress, outerwear, shoes, accessory, other }

enum LookState { draft, saved }

String checkedId(String value, String field) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
    throw FormatException('Invalid $field');
  }
  return value;
}

String requiredText(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty || value.length > 200) {
    throw FormatException('Invalid $key');
  }
  return value;
}

DateTime dateField(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || !value.endsWith('Z'))
    throw FormatException('Invalid $key');
  return DateTime.parse(value).toUtc();
}

void checkVersion(Map<String, dynamic> json) {
  if (json['schemaVersion'] != 1)
    throw const FormatException('Unsupported schema version');
}

void checkDates(DateTime created, DateTime updated) {
  if (!created.isUtc || !updated.isUtc || updated.isBefore(created)) {
    throw const FormatException('Invalid record timestamps');
  }
}

T enumValue<T extends Enum>(List<T> values, Object? name) => values.firstWhere(
  (v) => v.name == name,
  orElse: () => throw const FormatException('Unknown enum value'),
);

class PrivateImageRef {
  final String ownerId;
  final String imageId;
  final ImageKind kind;
  final DateTime? expiresAt;
  PrivateImageRef({
    required String ownerId,
    required String imageId,
    required this.kind,
    this.expiresAt,
  }) : ownerId = checkedId(ownerId, 'ownerId'),
       imageId = checkedId(imageId, 'imageId') {
    if (expiresAt != null && !expiresAt!.isUtc) {
      throw const FormatException('Image expiry must use UTC');
    }
    if (kind == ImageKind.referencePhoto && expiresAt == null) {
      throw const FormatException('Reference images require an expiry');
    }
  }
  String get objectKey {
    final prefix = switch (kind) {
      ImageKind.wardrobe => 'wardrobe',
      ImageKind.referencePhoto => 'reference-photos',
      ImageKind.savedLook => 'saved-looks',
    };
    return '$prefix/$ownerId/$imageId.jpg';
  }

  bool isExpired(DateTime now) =>
      expiresAt != null && !now.toUtc().isBefore(expiresAt!);
  Map<String, dynamic> toJson() => {
    'ownerId': ownerId,
    'imageId': imageId,
    'kind': kind.name,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
  };
  factory PrivateImageRef.fromJson(Map<String, dynamic> json) =>
      PrivateImageRef(
        ownerId: requiredText(json, 'ownerId'),
        imageId: requiredText(json, 'imageId'),
        kind: enumValue(ImageKind.values, json['kind']),
        expiresAt: json['expiresAt'] == null
            ? null
            : dateField(json, 'expiresAt'),
      );
}

class WardrobeItem {
  final String id;
  final String ownerId;
  final String name;
  final GarmentCategory category;
  final String? color;
  final PrivateImageRef? image;
  final DateTime createdAt;
  final DateTime updatedAt;
  WardrobeItem({
    required String id,
    required String ownerId,
    required this.name,
    required this.category,
    this.color,
    this.image,
    required this.createdAt,
    required this.updatedAt,
  }) : id = checkedId(id, 'id'),
       ownerId = checkedId(ownerId, 'ownerId') {
    checkDates(createdAt, updatedAt);
    if (name.trim().isEmpty ||
        name.length > 100 ||
        (color != null && color!.length > 50)) {
      throw const FormatException('Invalid garment description');
    }
    if (image != null &&
        (image!.ownerId != ownerId || image!.kind != ImageKind.wardrobe)) {
      throw const FormatException('Garment image ownership mismatch');
    }
  }
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'ownerId': ownerId,
    'name': name,
    'category': category.name,
    if (color != null) 'color': color,
    if (image != null) 'image': image!.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory WardrobeItem.fromJson(Map<String, dynamic> json) {
    checkVersion(json);
    if (json['color'] != null && json['color'] is! String)
      throw const FormatException('Invalid color');
    return WardrobeItem(
      id: requiredText(json, 'id'),
      ownerId: requiredText(json, 'ownerId'),
      name: requiredText(json, 'name'),
      category: enumValue(GarmentCategory.values, json['category']),
      color: json['color'] as String?,
      image: json['image'] == null
          ? null
          : PrivateImageRef.fromJson(
              Map<String, dynamic>.from(json['image'] as Map),
            ),
      createdAt: dateField(json, 'createdAt'),
      updatedAt: dateField(json, 'updatedAt'),
    );
  }
}

class ReferencePhoto {
  final String id;
  final String ownerId;
  final PrivateImageRef image;
  final DateTime createdAt;
  final DateTime consentedAt;
  final DateTime expiresAt;
  ReferencePhoto({
    required String id,
    required String ownerId,
    required this.image,
    required this.createdAt,
    required this.consentedAt,
    required this.expiresAt,
  }) : id = checkedId(id, 'id'),
       ownerId = checkedId(ownerId, 'ownerId') {
    checkDates(consentedAt, createdAt);
    if (!expiresAt.isUtc ||
        !expiresAt.isAfter(consentedAt) ||
        expiresAt.isAfter(createdAt.add(const Duration(days: 7)))) {
      throw const FormatException(
        'Reference photo retention exceeds seven days',
      );
    }
    if (image.ownerId != ownerId ||
        image.kind != ImageKind.referencePhoto ||
        image.imageId != id ||
        image.expiresAt != expiresAt) {
      throw const FormatException(
        'Reference photo ownership or expiry mismatch',
      );
    }
  }
  bool canUse(DateTime now) =>
      !now.toUtc().isBefore(createdAt) && now.toUtc().isBefore(expiresAt);
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'ownerId': ownerId,
    'image': image.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'consentedAt': consentedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };
  factory ReferencePhoto.fromJson(Map<String, dynamic> json) {
    checkVersion(json);
    return ReferencePhoto(
      id: requiredText(json, 'id'),
      ownerId: requiredText(json, 'ownerId'),
      image: PrivateImageRef.fromJson(
        Map<String, dynamic>.from(json['image'] as Map),
      ),
      createdAt: dateField(json, 'createdAt'),
      consentedAt: dateField(json, 'consentedAt'),
      expiresAt: dateField(json, 'expiresAt'),
    );
  }
}

class OwnedItemId {
  final String ownerId;
  final String id;
  OwnedItemId({required String ownerId, required String id})
    : ownerId = checkedId(ownerId, 'ownerId'),
      id = checkedId(id, 'id');
  Map<String, dynamic> toJson() => {'ownerId': ownerId, 'id': id};
  factory OwnedItemId.fromJson(Map<String, dynamic> json) => OwnedItemId(
    ownerId: requiredText(json, 'ownerId'),
    id: requiredText(json, 'id'),
  );
}

class SavedLook {
  final String id;
  final String ownerId;
  final String title;
  final List<OwnedItemId> items;
  final OwnedItemId? referencePhoto;
  final PrivateImageRef? preview;
  final LookState state;
  final DateTime createdAt;
  final DateTime updatedAt;
  SavedLook({
    required String id,
    required String ownerId,
    required this.title,
    required List<OwnedItemId> items,
    this.referencePhoto,
    this.preview,
    this.state = LookState.draft,
    required this.createdAt,
    required this.updatedAt,
  }) : id = checkedId(id, 'id'),
       ownerId = checkedId(ownerId, 'ownerId'),
       items = List.unmodifiable(items) {
    checkDates(createdAt, updatedAt);
    if (title.trim().isEmpty ||
        title.length > 100 ||
        items.isEmpty ||
        items.length > 20 ||
        items.map((i) => i.id).toSet().length != items.length ||
        items.any((i) => i.ownerId != ownerId) ||
        (referencePhoto != null && referencePhoto!.ownerId != ownerId) ||
        (preview != null &&
            (preview!.ownerId != ownerId ||
                preview!.kind != ImageKind.savedLook))) {
      throw const FormatException('Invalid saved look or cross-user reference');
    }
    if (state == LookState.saved && preview == null) {
      throw const FormatException('Saved looks require a private preview');
    }
  }
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'ownerId': ownerId,
    'title': title,
    'items': items.map((i) => i.toJson()).toList(),
    if (referencePhoto != null) 'referencePhoto': referencePhoto!.toJson(),
    if (preview != null) 'preview': preview!.toJson(),
    'state': state.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory SavedLook.fromJson(Map<String, dynamic> json) {
    checkVersion(json);
    if (json['items'] is! List)
      throw const FormatException('Missing garment references');
    return SavedLook(
      id: requiredText(json, 'id'),
      ownerId: requiredText(json, 'ownerId'),
      title: requiredText(json, 'title'),
      items: (json['items'] as List)
          .map((i) => OwnedItemId.fromJson(Map<String, dynamic>.from(i as Map)))
          .toList(),
      referencePhoto: json['referencePhoto'] == null
          ? null
          : OwnedItemId.fromJson(
              Map<String, dynamic>.from(json['referencePhoto'] as Map),
            ),
      preview: json['preview'] == null
          ? null
          : PrivateImageRef.fromJson(
              Map<String, dynamic>.from(json['preview'] as Map),
            ),
      state: enumValue(LookState.values, json['state']),
      createdAt: dateField(json, 'createdAt'),
      updatedAt: dateField(json, 'updatedAt'),
    );
  }
}
