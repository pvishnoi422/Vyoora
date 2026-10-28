import 'package:flutter/material.dart';

class FashionScreen extends StatelessWidget {
  const FashionScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fashion')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Make room for your style',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Keep your wardrobe, reference photos, and favorite looks together.',
        ),
        const SizedBox(height: 24),
        _Destination(
          icon: Icons.checkroom_outlined,
          title: 'Wardrobe',
          subtitle: 'A place for the pieces you love',
          route: '/wardrobe',
        ),
        _Destination(
          icon: Icons.photo_library_outlined,
          title: 'Reference photos',
          subtitle: 'Private photos with a limited retention period',
          route: '/fashion/reference-photos',
        ),
        _Destination(
          icon: Icons.bookmark_border,
          title: 'Saved looks',
          subtitle: 'Keep outfits you want to return to',
          route: '/fashion/saved-looks',
        ),
        const SizedBox(height: 20),
        const Text(
          'Photo uploads require a verified account. Your photos are never public by default.',
        ),
      ],
    ),
  );
}

class _Destination extends StatelessWidget {
  final IconData icon;
  final String title, subtitle, route;
  const _Destination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.pushNamed(context, route),
    ),
  );
}

class WardrobeScreen extends StatelessWidget {
  const WardrobeScreen({super.key});
  @override
  Widget build(BuildContext context) => const _CollectionScreen(
    title: 'Wardrobe',
    icon: Icons.checkroom_outlined,
    message: 'Your wardrobe starts here',
    description:
        'Keep your garments organized by category, color, and private photos.',
    showCategories: true,
  );
}

class ReferencePhotosScreen extends StatelessWidget {
  const ReferencePhotosScreen({super.key});
  @override
  Widget build(BuildContext context) => const _CollectionScreen(
    title: 'Reference photos',
    icon: Icons.photo_library_outlined,
    message: 'A private space for your photos',
    description:
        'A verified account and your consent are required before adding a reference photo. Reference photos expire after seven days.',
  );
}

class SavedLooksScreen extends StatelessWidget {
  const SavedLooksScreen({super.key});
  @override
  Widget build(BuildContext context) => const _CollectionScreen(
    title: 'Saved looks',
    icon: Icons.bookmark_border,
    message: 'No saved looks yet',
    description:
        'Saved looks will keep their garment references and preview images private to your account.',
    showWardrobeLink: true,
  );
}

class _CollectionScreen extends StatelessWidget {
  final String title, message, description;
  final IconData icon;
  final bool showCategories, showWardrobeLink;
  const _CollectionScreen({
    required this.title,
    required this.message,
    required this.description,
    required this.icon,
    this.showCategories = false,
    this.showWardrobeLink = false,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(icon, size: 64),
        const SizedBox(height: 24),
        Text(message, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(description),
        if (showCategories) ...[
          const SizedBox(height: 24),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Tops')),
              Chip(label: Text('Bottoms')),
              Chip(label: Text('Dresses')),
              Chip(label: Text('Outerwear')),
              Chip(label: Text('Shoes')),
              Chip(label: Text('Accessories')),
            ],
          ),
        ],
        if (showWardrobeLink) ...[
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => Navigator.pushNamed(context, '/wardrobe'),
            child: const Text('Explore wardrobe'),
          ),
        ],
      ],
    ),
  );
}
