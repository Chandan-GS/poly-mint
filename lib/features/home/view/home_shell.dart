import 'package:flutter/material.dart';

import '../../../core/theme/app_type.dart';
import '../../dashboard/view/dashboard_screen.dart';
import '../../history/view/history_screen.dart';
import '../../leaderboard/view/leaderboard_screen.dart';
import '../../scan/view/scan_screen.dart';
import '../../settings/view/settings_screen.dart';

/// Bottom-navigation host. Flat instrument nav bar (hairline top, mono labels)
/// with a single emphasised SCAN action in the centre.
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                _NavItem(Icons.grid_view_outlined, Icons.grid_view, 'HOME',
                    _index == 0, () => setState(() => _index = 0)),
                _NavItem(Icons.receipt_long_outlined, Icons.receipt_long,
                    'LOG', _index == 1, () => setState(() => _index = 1)),
                _ScanAction(onTap: _openScan),
                _NavItem(Icons.bar_chart_outlined, Icons.bar_chart, 'RANKS',
                    _index == 2, () => setState(() => _index = 2)),
                _NavItem(Icons.tune_outlined, Icons.tune, 'CONFIG',
                    _index == 3, () => setState(() => _index = 3)),
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
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem(
      this.icon, this.activeIcon, this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, color: color, size: 21),
            const SizedBox(height: 3),
            Text(label,
                style: AppType.monoSmall.copyWith(
                    color: color, fontSize: 9.5, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

/// Centre SCAN action — a flat accent block, not a floating circle.
class _ScanAction extends StatelessWidget {
  final VoidCallback onTap;
  const _ScanAction({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Material(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.center_focus_strong,
                    color: scheme.onPrimary, size: 20),
                const SizedBox(height: 2),
                Text('SCAN',
                    style: AppType.monoSmall.copyWith(
                        color: scheme.onPrimary,
                        fontSize: 9.5,
                        letterSpacing: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
