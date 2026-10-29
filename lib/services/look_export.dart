import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native exports work on copies; private originals are never uploaded again.
class LookExport {
  static const channel = MethodChannel('vyoora/exports');
  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  Future<String?> save(Uint8List bytes) async {
    _check();
    return channel.invokeMethod<String>('save', bytes);
  }

  Future<bool> share(Uint8List bytes) async {
    _check();
    return await channel.invokeMethod<bool>('share', bytes) ?? false;
  }

  void _check() {
    if (!supported) {
      throw PlatformException(
        code: 'ios_required',
        message: 'Open the iOS app to save to Photos or share.',
      );
    }
  }
}
