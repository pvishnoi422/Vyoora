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
          icon: Icons.auto_awesome,
          title: 'Try on',
          subtitle: 'See a saved garment on your private reference photo',
          route: '/fashion/try-on',
        ),
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
          title: 'My Looks',
          subtitle: 'Keep outfits you want to return to',
          route: '/fashion/saved-looks',
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => Navigator.pushNamed(context, '/fashion/privacy'),
          child: const Text('Photo privacy'),
        ),
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
