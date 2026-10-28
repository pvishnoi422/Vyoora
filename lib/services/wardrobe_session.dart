import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WardrobeFailure implements Exception {
  final String message;
  const WardrobeFailure(this.message);
  @override
  String toString() => message;
}

/// Firebase REST sessions stay in memory; passwords and tokens are never saved
/// to preferences, URLs or logs. Firebase refresh tokens renew short-lived IDs.
class WardrobeSession extends ChangeNotifier {
  static final instance = WardrobeSession();
  final http.Client client;
  final String apiKey, project, emulator;
  String? uid, email, _idToken, _refreshToken;
  DateTime _expires = DateTime(1970);
  int _generation = 0;
  Future<String>? _refreshing;

  WardrobeSession({
    http.Client? client,
    this.apiKey = const String.fromEnvironment('FIREBASE_API_KEY'),
    this.project = const String.fromEnvironment('FIREBASE_PROJECT_ID'),
    this.emulator = const String.fromEnvironment('AUTH_EMULATOR_HOST'),
  }) : client = client ?? http.Client() {
    if (emulator.isNotEmpty &&
        (kReleaseMode ||
            !project.startsWith('demo-') ||
            !{
              'localhost',
              '127.0.0.1',
            }.contains(Uri.parse('http://$emulator').host))) {
      throw StateError('Auth emulator requires a local debug demo project');
    }
  }

  bool get configured =>
      project.isNotEmpty && (apiKey.isNotEmpty || emulator.isNotEmpty);
  bool get signedIn => uid != null;
  Uri _uri(String method, {bool refresh = false}) {
    final host = refresh
        ? 'securetoken.googleapis.com'
        : 'identitytoolkit.googleapis.com';
    final path = refresh ? '/v1/token' : '/v1/accounts:$method';
    return emulator.isEmpty
        ? Uri.https(host, path, {'key': apiKey})
        : Uri.parse('http://$emulator/$host$path?key=demo-key');
  }

  Future<Map<String, dynamic>> _call(
    String method,
    Map<String, dynamic> data,
  ) async {
    final response = await client
        .post(
          _uri(method),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 20));
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final code = (result['error'] as Map?)?['message'];
      throw WardrobeFailure(switch (code) {
        'EMAIL_EXISTS' =>
          'An account already exists with this email. Please sign in.',
        'TOO_MANY_ATTEMPTS_TRY_LATER' =>
          'Too many attempts. Please try again later.',
        'WEAK_PASSWORD : Password should be at least 6 characters' =>
          'Choose a stronger password.',
        _ =>
          'Could not sign in. Check your email and password, then try again.',
      });
    }
    return result;
  }

  Future<void> signIn(
    String address,
    String password, {
    bool create = false,
  }) async {
    if (!configured)
      throw const WardrobeFailure(
        'Account sign-in has not been configured for this build.',
      );
    final generation = ++_generation;
    final data = await _call(create ? 'signUp' : 'signInWithPassword', {
      'email': address.trim(),
      'password': password,
      'returnSecureToken': true,
    });
    if (generation != _generation) return;
    uid = data['localId'] as String;
    email = data['email'] as String;
    _idToken = data['idToken'] as String;
    _refreshToken = data['refreshToken'] as String;
    _expires = DateTime.now().add(
      Duration(seconds: int.parse(data['expiresIn'].toString()) - 60),
    );
    notifyListeners();
    if (create) await sendVerification();
  }

  Future<void> sendVerification() async {
    await _call('sendOobCode', {
      'requestType': 'VERIFY_EMAIL',
      'idToken': await token(),
    });
  }

  Future<String> token({bool forceRefresh = false}) async {
    if (_refreshToken == null)
      throw const WardrobeFailure('Please sign in to your wardrobe.');
    if (!forceRefresh && DateTime.now().isBefore(_expires) && _idToken != null)
      return _idToken!;
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh() async {
    final generation = _generation;
    final response = await client
        .post(
          _uri('', refresh: true),
          body: {
            'grant_type': 'refresh_token',
            'refresh_token': _refreshToken!,
          },
        )
        .timeout(const Duration(seconds: 20));
    if (generation != _generation)
      throw const WardrobeFailure('Your account changed. Please try again.');
    if (response.statusCode != 200) {
      signOut();
      throw const WardrobeFailure(
        'Your session expired. Please sign in again.',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _idToken = data['id_token'] as String;
    _refreshToken = data['refresh_token'] as String;
    _expires = DateTime.now().add(
      Duration(seconds: int.parse(data['expires_in'].toString()) - 60),
    );
    return _idToken!;
  }

  void signOut() {
    _generation++;
    uid = email = _idToken = _refreshToken = null;
    _refreshing = null;
    _expires = DateTime(1970);
    notifyListeners();
  }
}
