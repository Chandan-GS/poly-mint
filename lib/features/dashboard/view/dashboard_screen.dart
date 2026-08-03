import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../data/models/impact_stats.dart';
import '../../../data/models/polymer_info.dart';
import '../../../data/services/preferences_service.dart';
import '../../../data/services/transaction_repository.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../cubit/dashboard_cubit.dart';
import '../widgets/impact_charts.dart';
import 'transaction_tile.dart';

class DashboardScreen extends StatelessWidget {
  /// Callback wired by [HomeShell] to jump to the scan tab.
  final VoidCallback onScanRequested;
  const DashboardScreen({super.key, required this.onScanRequested});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DashboardCubit(
        sl<TransactionRepository>(),
        sl<PreferencesService>().userId,
      ),
      child: _DashboardView(onScanRequested: onScanRequested),
    );
  }
}

class _DashboardView extends StatelessWidget {
  final VoidCallback onScanRequested;
  const _DashboardView({required this.onScanRequested});

  @override
  Widget build(BuildContext context) {
    final name = context.select((SettingsCubit c) => c.state.displayName);

    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<DashboardCubit, DashboardState>(
          builder: (context, state) {
            if (state.status == DashboardStatus.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            final s = state.userStats;
            return RefreshIndicator(
              onRefresh: () async =>
                  Future.delayed(const Duration(milliseconds: 400)),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _Greeting(name: name),
                  const SizedBox(height: 16),
                  if (state.pendingCount > 0) ...[
                    _PendingBanner(count: state.pendingCount),
                    const SizedBox(height: 16),
                  ],
                  _CreditsHero(stats: s),
                  const SizedBox(height: 16),
                  _StatGrid(stats: s),
                  const SizedBox(height: 20),
                  _ImpactEquivalences(stats: s),
                  const SizedBox(height: 24),
                  if (s.scanCount > 0) ...[
                    const SectionHeader(title: 'Material breakdown'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: PolymerBreakdownChart(stats: s),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'This week'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: WeeklyTrendChart(stats: s),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  SectionHeader(
                    title: 'Recent activity',
                    trailing: state.recent.isEmpty
                        ? null
                        : Text('${s.scanCount} total',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                  ),
                  if (state.recent.isEmpty)
                    _FirstScanPrompt(onScan: onScanRequested)
                  else
                    ...state.recent.map((t) => TransactionTile(txn: t)),
                  const SizedBox(height: 24),
                  _GlobalExchangeCard(stats: state.globalStats),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  final String name;
  const _Greeting({required this.name});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(greeting,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(name,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _CreditsHero extends StatelessWidget {
  final ImpactStats stats;
  const _CreditsHero({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B8A5A), Color(0xFF0F5C3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.workspace_premium, color: Colors.white70, size: 18),
              SizedBox(width: 6),
              Text('YOUR VERIFIED CREDITS',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 12),
          Text(Formatters.credits(stats.totalCredits),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 46,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('${Formatters.weight(stats.totalWeightKg)} recovered · '
              '${Formatters.co2(stats.totalCo2SavedKg)} CO₂ avoided',
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  final ImpactStats stats;
  const _StatGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final top = stats.topPolymerCode;
    return Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.qr_code_scanner,
            label: 'Batches scanned',
            value: '${stats.scanCount}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: Icons.category,
            label: 'Top material',
            accent: top == null ? null : PolymerCatalog.lookup(top).color,
            value: top == null ? '—' : PolymerCatalog.lookup(top).shortName,
          ),
        ),
      ],
    );
  }
}

class _ImpactEquivalences extends StatelessWidget {
  final ImpactStats stats;
  const _ImpactEquivalences({required this.stats});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _Equiv(
              icon: Icons.park,
              color: const Color(0xFF16A34A),
              value: stats.treesEquivalent.toStringAsFixed(1),
              label: 'trees / yr',
            ),
            _divider(scheme),
            _Equiv(
              icon: Icons.local_gas_station,
              color: const Color(0xFFF59E0B),
              value: Formatters.compact(stats.litresPetrolEquivalent),
              label: 'L petrol',
            ),
            _divider(scheme),
            _Equiv(
              icon: Icons.co2,
              color: const Color(0xFF2563EB),
              value: Formatters.compact(stats.totalCo2SavedKg),
              label: 'kg CO₂',
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(ColorScheme scheme) => Container(
      width: 1, height: 40, color: scheme.outlineVariant.withValues(alpha: 0.5));
}

class _Equiv extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _Equiv(
      {required this.icon,
      required this.color,
      required this.value,
      required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  final int count;
  const _PendingBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_sync, color: Color(0xFFF59E0B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count batch${count == 1 ? '' : 'es'} waiting to sync. '
              'They’ll upload automatically when you’re back online.',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstScanPrompt extends StatelessWidget {
  final VoidCallback onScan;
  const _FirstScanPrompt({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.recycling, size: 40, color: Color(0xFF1B8A5A)),
            const SizedBox(height: 12),
            const Text('Scan your first batch',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Text('Recover plastic, verify it with AI, and start minting credits.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Start scanning'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlobalExchangeCard extends StatelessWidget {
  final ImpactStats stats;
  const _GlobalExchangeCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.public, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                const Text('Global exchange',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    value: Formatters.compact(stats.totalCredits),
                    label: 'credits minted',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    value: Formatters.compact(stats.totalWeightKg),
                    label: 'kg recovered',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    value: '${stats.scanCount}',
                    label: 'batches',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  const _MiniStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
