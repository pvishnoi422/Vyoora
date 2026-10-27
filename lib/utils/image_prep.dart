import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Auto-rotate (EXIF), resize to <= 1600px, and JPEG-encode (quality 80).
Future<Uint8List> preprocessForOCR(Uint8List bytes) async {
  final src = img.decodeImage(bytes);
  if (src == null) return bytes;

  // Fix orientation from EXIF if present
  final oriented = img.bakeOrientation(src);

  // Bound the longer side to 1600px (keeps detail, shrinks huge photos)
  final w = oriented.width, h = oriented.height;
  final maxSide = 1600;
  img.Image resized = oriented;
  if (w > maxSide || h > maxSide) {
    resized = img.copyResize(oriented,
        width: w >= h ? maxSide : (w * maxSide ~/ h),
        height: h > w ? maxSide : (h * maxSide ~/ w));
  }

  // Light contrast pop (optional, tiny bump)
  // final boosted = img.adjustColor(resized, contrast: 0.05);

  // Encode as JPEG ~80% for faster uploads/OCR
  final jpg = img.encodeJpg(resized, quality: 80);
  return Uint8List.fromList(jpg);
}
