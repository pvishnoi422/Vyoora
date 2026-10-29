import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/fashion/domain.dart';
import '../models/fashion/tryon_job.dart';
import 'wardrobe_repository.dart';
import 'wardrobe_session.dart';

const tryOnConsentVersion = 'google-tryon-v1';
const tryOnCategories = {
  GarmentCategory.top,
  GarmentCategory.bottom,
  GarmentCategory.dress,
  GarmentCategory.outerwear,
};

class TryOnAvailability {
  final bool enabled;
  final int remainingToday, dailyLimit;
  const TryOnAvailability(this.enabled, this.remainingToday, this.dailyLimit);
}

class SavedLooksPage {
  final List<SavedLook> items;
  final String? nextPageToken;
  const SavedLooksPage(this.items, this.nextPageToken);
}

class TryOnRepository extends WardrobeRepository {
  TryOnRepository({required super.session, super.client, super.base});
  Uri _uri(String path) => Uri.parse('$base/v2/$path');
  static String newJobId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  ReferencePhoto _photo(Object? value) {
    final photo = ReferencePhoto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    if (photo.ownerId != session.uid)
      throw const WardrobeFailure('Photo ownership could not be verified.');
    return photo;
  }

  TryOnJob _job(Object? value) {
    final job = TryOnJob.fromJson(Map<String, dynamic>.from(value as Map));
    if (job.ownerId != session.uid)
      throw const WardrobeFailure(
        'Generation ownership could not be verified.',
      );
    return job;
  }

  Future<List<ReferencePhoto>> references() async {
    final response = await sendAuthenticated(
      http.Request('GET', _uri('reference-photos')),
    );
    return ((jsonDecode(response.body) as Map)['items'] as List)
        .map(_photo)
        .toList();
  }

  Future<ReferencePhoto> uploadReference(Uint8List bytes) async {
    if (bytes.length > 5 * 1024 * 1024)
      throw const WardrobeFailure('Choose a photo smaller than 5 MB.');
    final request = http.MultipartRequest('POST', _uri('reference-photos'))
      ..fields.addAll({
        'consent': 'granted',
        'consentVersion': tryOnConsentVersion,
        'adultPermission': 'confirmed',
      })
      ..files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: 'reference.jpg'),
      );
    final response = await sendAuthenticated(request);
    return _photo((jsonDecode(response.body) as Map)['item']);
  }

  Future<Uint8List> referenceImage(String id) async => (await sendAuthenticated(
    http.Request('GET', _uri('reference-photos/${checkedId(id, 'id')}/image')),
  )).bodyBytes;
  Future<void> deleteReference(String id) async {
    await sendAuthenticated(
      http.Request('DELETE', _uri('reference-photos/${checkedId(id, 'id')}')),
    );
  }

  Future<TryOnAvailability> availability() async {
    final response = await sendAuthenticated(
      http.Request('GET', _uri('try-on/availability')),
    );
    final data = jsonDecode(response.body) as Map;
    return TryOnAvailability(
      data['enabled'] == true,
      data['remainingToday'] as int,
      data['dailyLimit'] as int,
    );
  }

  Future<List<TryOnJob>> jobs() async {
    final response = await sendAuthenticated(
      http.Request('GET', _uri('try-on/jobs')),
    );
    return ((jsonDecode(response.body) as Map)['items'] as List)
        .map(_job)
        .toList();
  }

  Future<TryOnJob> createJob({
    required String id,
    required String garmentId,
    required String referenceId,
  }) async {
    final request = http.Request('POST', _uri('try-on/jobs'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'jobId': checkedId(id, 'id'),
        'garmentId': checkedId(garmentId, 'garmentId'),
        'referenceId': checkedId(referenceId, 'referenceId'),
        'consentVersion': tryOnConsentVersion,
      });
    return _job(
      (jsonDecode((await sendAuthenticated(request)).body) as Map)['job'],
    );
  }

  Future<TryOnJob> job(String id) async => _job(
    (jsonDecode(
          (await sendAuthenticated(
            http.Request('GET', _uri('try-on/jobs/${checkedId(id, 'id')}')),
          )).body,
        )
        as Map)['job'],
  );
  Future<TryOnJob> cancel(String id) async => _job(
    (jsonDecode(
          (await sendAuthenticated(
            http.Request('DELETE', _uri('try-on/jobs/${checkedId(id, 'id')}')),
          )).body,
        )
        as Map)['job'],
  );
  Future<Uint8List> preview(String id) async => (await sendAuthenticated(
    http.Request('GET', _uri('try-on/jobs/${checkedId(id, 'id')}/image')),
  )).bodyBytes;

  SavedLook _look(Object? value) {
    final look = SavedLook.fromJson(Map<String, dynamic>.from(value as Map));
    if (look.ownerId != session.uid ||
        look.preview?.imageId != look.id ||
        look.preview?.expiresAt == null) {
      throw const WardrobeFailure(
        'Look ownership or retention could not be verified.',
      );
    }
    return look;
  }

  Future<SavedLooksPage> looks({String? pageToken}) async {
    final url = _uri('saved-looks').replace(
      queryParameters: pageToken == null ? null : {'pageToken': pageToken},
    );
    final data =
        jsonDecode((await sendAuthenticated(http.Request('GET', url))).body)
            as Map;
    return SavedLooksPage(
      (data['items'] as List).map(_look).toList(),
      data['nextPageToken'] as String?,
    );
  }

  Future<SavedLook> saveLook(String jobId, String title) async {
    final request = http.Request('POST', _uri('saved-looks'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'jobId': checkedId(jobId, 'jobId'),
        'title': title,
        'consentVersion': 'saved-looks-v1',
      });
    return _look(
      (jsonDecode((await sendAuthenticated(request)).body) as Map)['item'],
    );
  }

  Future<Uint8List> lookImage(String id) async => (await sendAuthenticated(
    http.Request('GET', _uri('saved-looks/${checkedId(id, 'id')}/image')),
  )).bodyBytes;
  Future<void> deleteLook(String id) async {
    await sendAuthenticated(
      http.Request('DELETE', _uri('saved-looks/${checkedId(id, 'id')}')),
    );
  }
}
