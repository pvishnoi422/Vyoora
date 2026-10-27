// lib/screens/home_shell.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../upload_screen.dart';
import '../screens/history_screen.dart';
import '../components/chat_screen.dart';
import '../screens/profile_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  int _index    = 0;
  int _prevIndex = 0;
  late AnimationController _transCtrl;
  late Animation<double>   _transAnim;

  final _screens = const [
    UploadScreen(),
    HistoryScreen(),
    ChatScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _transCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _transAnim =
        CurvedAnimation(parent: _transCtrl, curve: Curves.easeOutCubic);
    _transCtrl.value = 1.0;
  }

  @override
  void dispose() {
    _transCtrl.dispose();
    super.dispose();
  }

  void _switchTab(int i) {
    if (i == _index) return;
    setState(() => _prevIndex = _index);
    _transCtrl.value = 0;
    setState(() => _index = i);
    _transCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: AnimatedBuilder(
        animation: _transAnim,
        builder: (_, __) {
          return Opacity(
            opacity: _transAnim.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - _transAnim.value)),
              child: IndexedStack(index: _index, children: _screens),
            ),
          );
        },
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF080808),
          border: Border(
            top: BorderSide(color: const Color(0xFFD4AF37).withOpacity(0.12)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(icon: Icons.home_outlined,       activeIcon: Icons.home,        label: 'Home',     index: 0, current: _index, onTap: _switchTab),
                _NavItem(icon: Icons.history_outlined,    activeIcon: Icons.history,     label: 'History',  index: 1, current: _index, onTap: _switchTab),
                _NavItem(icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble, label: 'Ask Lumi', index: 2, current: _index, onTap: _switchTab),
                _NavItem(icon: Icons.person_outline,      activeIcon: Icons.person,      label: 'Profile',  index: 3, current: _index, onTap: _switchTab),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String   label;
  final int      index;
  final int      current;
  final void Function(int) onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                active ? activeIcon : icon,
                key: ValueKey(active),
                color: active
                    ? const Color(0xFFD4AF37)
                    : Colors.white.withOpacity(0.7),
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.cormorantGaramond(
                color: active
                    ? const Color(0xFFD4AF37)
                    : Colors.white.withOpacity(0.7),
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
