import 'package:flutter/material.dart';
import '../screens/fashion/fashion_screen.dart';
import '../screens/fashion/wardrobe_screen.dart';
import '../screens/fashion/tryon_screen.dart';
import '../screens/fashion/reference_photos_screen.dart';

Map<String, WidgetBuilder> get fashionRoutes => {
  '/fashion': (_) => const FashionScreen(),
  '/wardrobe': (_) => const WardrobeScreen(),
  '/fashion/try-on': (context) {
    final id = ModalRoute.of(context)?.settings.arguments;
    final garment = id is String ? id : (id is Map ? id['garmentId'] : null);
    final reference = id is Map ? id['referenceId'] : null;
    return TryOnScreen(
      initialGarmentId: garment is String ? garment : null,
      initialReferenceId: reference is String ? reference : null,
    );
  },
  '/fashion/reference-photos': (_) => const ReferencePhotosScreen(),
  '/fashion/saved-looks': (_) => const SavedLooksScreen(),
};
