import 'package:flutter/material.dart';
import '../screens/fashion/fashion_screen.dart';

Map<String, WidgetBuilder> get fashionRoutes => {
  '/fashion': (_) => const FashionScreen(),
  '/wardrobe': (_) => const WardrobeScreen(),
  '/fashion/reference-photos': (_) => const ReferencePhotosScreen(),
  '/fashion/saved-looks': (_) => const SavedLooksScreen(),
};
