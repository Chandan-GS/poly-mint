import 'package:flutter/material.dart';

import '../../dashboard/view/dashboard_screen.dart';
import '../../history/view/history_screen.dart';
import '../../leaderboard/view/leaderboard_screen.dart';
import '../../scan/view/scan_screen.dart';
import '../../settings/view/settings_screen.dart';

/// Bottom-navigation host. Keeps each tab alive via [IndexedStack] and exposes
/// a prominent central Scan action that pushes the camera flow.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _openScan() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      DashboardScreen(onScanRequested: _openScan),
      HistoryScreen(onScanRequested: _openScan),
      const LeaderboardScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: _openScan,
        elevation: 2,
        child: const Icon(Icons.camera_alt, size: 28),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 64,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
                icon: Icons.dashboard_outlined,
                activeIcon: Icons.dashboard,
                label: 'Home',
                selected: _index == 0,
                onTap: () => setState(() => _index = 0)),
            _NavItem(
                icon: Icons.history,
                activeIcon: Icons.history,
                label: 'History',
                selected: _index == 1,
                onTap: () => setState(() => _index = 1)),
            const SizedBox(width: 48), // notch gap
            _NavItem(
                icon: Icons.leaderboard_outlined,
                activeIcon: Icons.leaderboard,
                label: 'Ranks',
                selected: _index == 2,
                onTap: () => setState(() => _index = 2)),
            _NavItem(
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                label: 'Settings',
                selected: _index == 3,
                onTap: () => setState(() => _index = 3)),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? activeIcon : icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
