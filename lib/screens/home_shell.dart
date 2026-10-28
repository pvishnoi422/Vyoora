import 'package:flutter/material.dart';
import '../upload_screen.dart';
import 'history_screen.dart';
import '../components/chat_screen.dart';
import 'profile_screen.dart';
import 'fashion/fashion_screen.dart';

class HomeShell extends StatefulWidget {
  /// Optional hosts make the shell reusable and keep route tests independent
  /// of network fonts, scan storage, and the individual feature screens.
  final List<Widget>? primaryScreens;
  const HomeShell({super.key, this.primaryScreens});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  final Set<int> _visited = {0};
  late AnimationController _transition;

  @override
  void initState() {
    super.initState();
    _transition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1,
    );
  }

  @override
  void dispose() {
    _transition.dispose();
    super.dispose();
  }

  void _switchTab(int index) {
    if (index == _index) return;
    setState(() {
      _index = index;
      _visited.add(index);
    });
    _transition.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final primary =
        widget.primaryScreens ??
        const [UploadScreen(), HistoryScreen(), ChatScreen(), ProfileScreen()];
    assert(primary.length == 4);
    final screens = [
      primary[0],
      const FashionScreen(),
      primary[1],
      primary[2],
      primary[3],
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _transition, curve: Curves.easeOut),
        child: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < screens.length; i++)
              _visited.contains(i) ? screens[i] : const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF080808),
        indicatorColor: const Color(0xFFD4AF37).withValues(alpha: 0.2),
        selectedIndex: _index,
        onDestinationSelected: _switchTab,
        destinations: const [
          NavigationDestination(
            key: Key('nav-home'),
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            key: Key('nav-fashion'),
            icon: Icon(Icons.checkroom_outlined),
            selectedIcon: Icon(Icons.checkroom),
            label: 'Fashion',
          ),
          NavigationDestination(
            key: Key('nav-history'),
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            key: Key('nav-chat'),
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Ask Lumi',
          ),
          NavigationDestination(
            key: Key('nav-profile'),
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
