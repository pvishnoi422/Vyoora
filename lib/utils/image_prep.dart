// lib/utils/image_prep.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Preprocesses an image for better OCR accuracy:
/// - Fixes EXIF orientation
/// - Resizes longest side to ≤ 1800px
/// - Boosts contrast slightly for label text
/// - Encodes as high-quality JPEG
Future<Uint8List> preprocessForOCR(Uint8List bytes) async {
  final src = img.decodeImage(bytes);
  if (src == null) return bytes;

  // Fix EXIF orientation (e.g. photos taken in portrait mode)
  final oriented = img.bakeOrientation(src);

  // Resize so longest side ≤ 1800px
  const maxSide = 1800;
  final w = oriented.width;
  final h = oriented.height;
  img.Image resized = oriented;
  if (w > maxSide || h > maxSide) {
    resized = img.copyResize(
      oriented,
      width:  w >= h ? maxSide : (w * maxSide ~/ h),
      height: h > w  ? maxSide : (h * maxSide ~/ w),
    );
  }

  // Contrast boost — helps OCR read text on glossy/uneven label backgrounds
  final boosted = img.adjustColor(resized, contrast: 1.15);

  // Encode as JPEG at 90% — good balance of quality and size
  final jpg = img.encodeJpg(boosted, quality: 90);
  return Uint8List.fromList(jpg);
}
