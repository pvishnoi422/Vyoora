import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/fashion/domain.dart';
import 'wardrobe_session.dart';

class WardrobePage {
  final List<WardrobeItem> items;
  final String? nextPageToken;
  const WardrobePage(this.items, this.nextPageToken);
}

class WardrobeRepository {
  final WardrobeSession session;
  final http.Client client;
  final String base;
  WardrobeRepository({
    required this.session,
    http.Client? client,
    this.base = const String.fromEnvironment('WARDROBE_API_BASE_URL'),
  }) : client = client ?? http.Client() {
    if (base.isNotEmpty) {
      final uri = Uri.parse(base);
      if (uri.scheme != 'https' &&
          !(!kReleaseMode &&
              uri.scheme == 'http' &&
              {'127.0.0.1', 'localhost'}.contains(uri.host))) {
        throw StateError('Wardrobe API requires HTTPS');
      }
    }
  }

  bool get configured => base.isNotEmpty && session.configured;
  Uri _url(String path, [String? page]) => Uri.parse(
    '$base/v2/wardrobe$path',
  ).replace(queryParameters: page == null ? null : {'pageToken': page});

  Future<http.Response> _send(http.BaseRequest request) async {
    final owner = session.uid;
    request.headers['Authorization'] = 'Bearer ${await session.token()}';
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 45)),
    ).timeout(const Duration(seconds: 45));
    if (owner == null || session.uid != owner) {
      throw const WardrobeFailure('Your account changed. Please try again.');
    }
    if (response.statusCode >= 400) {
      String? code;
      try {
        code = (jsonDecode(response.body) as Map)['code'] as String?;
      } catch (_) {
        /* sanitized below */
      }
      if (response.statusCode == 401) session.signOut();
      throw WardrobeFailure(switch (code) {
        'verified_account_required' =>
          'Verify your email before using your wardrobe. Then tap Refresh.',
        'authentication_required' =>
          'Your session expired. Please sign in again.',
        'image_too_large' => 'Choose a photo smaller than 5 MB.',
        'invalid_image' =>
          'Choose a single JPEG, PNG or WebP photo under 20 megapixels.',
        'not_found' =>
          'This garment is no longer available. Refresh your wardrobe.',
        _ =>
          'Your wardrobe could not be updated. Check your connection and try again.',
      });
    }
    return response;
  }

  WardrobeItem _item(Object? data) {
    final item = WardrobeItem.fromJson(Map<String, dynamic>.from(data as Map));
    if (item.ownerId != session.uid || item.image?.imageId != item.id) {
      throw const WardrobeFailure(
        'The wardrobe response could not be verified.',
      );
    }
    return item;
  }

  Future<WardrobePage> list({String? pageToken}) async {
    final response = await _send(http.Request('GET', _url('', pageToken)));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return WardrobePage(
      (data['items'] as List).map(_item).toList(),
      data['nextPageToken'] as String?,
    );
  }

  Future<WardrobeItem> upload({
    required Uint8List bytes,
    required String name,
    required GarmentCategory category,
    String? color,
  }) async {
    if (bytes.length > 5 * 1024 * 1024)
      throw const WardrobeFailure('Choose a photo smaller than 5 MB.');
    final request = http.MultipartRequest('POST', _url(''))
      ..fields.addAll({
        'name': name.trim(),
        'category': category.name,
        'color': color?.trim() ?? '',
        'consent': 'granted',
      })
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: 'garment.jpg',
          contentType: MediaType('application', 'octet-stream'),
        ),
      );
    final response = await _send(request);
    return _item((jsonDecode(response.body) as Map)['item']);
  }

  Future<Uint8List> image(String id) async => (await _send(
    http.Request('GET', _url('/${checkedId(id, 'id')}/image')),
  )).bodyBytes;
  Future<void> delete(String id) async {
    await _send(http.Request('DELETE', _url('/${checkedId(id, 'id')}')));
  }
}
