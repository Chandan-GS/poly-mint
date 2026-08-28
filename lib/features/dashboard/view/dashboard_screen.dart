import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
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

/// Bordered surface block — the instrument "panel".
class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  _Header(name: name),
                  const SizedBox(height: 20),
                  if (state.pendingCount > 0) ...[
                    _PendingBanner(count: state.pendingCount),
                    const SizedBox(height: 16),
                  ],
                  _HeroReadout(stats: s),
                  const SizedBox(height: 12),
                  _TripleStat(stats: s),
                  const SizedBox(height: 12),
                  _Equivalences(stats: s),
                  const SizedBox(height: 26),
                  if (s.scanCount > 0) ...[
                    const SectionLabel('Material breakdown'),
                    _Panel(child: PolymerBreakdownChart(stats: s)),
                    const SizedBox(height: 24),
                    const SectionLabel('This week'),
                    _Panel(child: WeeklyTrendChart(stats: s)),
                    const SizedBox(height: 24),
                  ],
                  SectionLabel(
                    'Recent activity',
                    trailing: state.recent.isEmpty
                        ? null
                        : Text('${s.scanCount} TOTAL',
                            style: AppType.monoSmall.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                  ),
                  if (state.recent.isEmpty)
                    _FirstScanPrompt(onScan: onScanRequested)
                  else
                    _Panel(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < state.recent.length; i++) ...[
                            if (i > 0)
                              Divider(
                                  height: 1,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant),
                            TransactionTile(txn: state.recent[i]),
                          ]
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  const SectionLabel('Global exchange'),
                  _GlobalExchange(stats: state.globalStats),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String name;
  const _Header({required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('POLYMINT',
                  style: AppType.label.copyWith(
                      color: scheme.onSurface, letterSpacing: 2.5)),
              const SizedBox(height: 4),
              Text('$greeting, $name',
                  style: AppType.caption
                      .copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        // live-node indicator
        Row(children: [
          Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('LIVE',
              style: AppType.monoSmall.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      ],
    );
  }
}

/// The money visual: physically verified mass, big and monospaced.
class _HeroReadout extends StatelessWidget {
  final ImpactStats stats;
  const _HeroReadout({required this.stats});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VERIFIED MASS',
              style: AppType.label.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              text: Formatters.compact(stats.totalWeightKg) == ''
                  ? '0'
                  : stats.totalWeightKg.toStringAsFixed(2),
              style: AppType.metricXL.copyWith(color: scheme.onSurface),
              children: [
                TextSpan(
                    text: '  kg',
                    style: AppType.metricM
                        .copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Metric(
                  label: 'Credits minted',
                  value: Formatters.credits(stats.totalCredits),
                  valueStyle: AppType.metricM,
                  valueColor: AppColors.accent,
                ),
              ),
              Expanded(
                child: Metric(
                  label: 'CO₂e avoided',
                  value: stats.totalCo2SavedKg.toStringAsFixed(1),
                  unit: 'kg',
                  valueStyle: AppType.metricM,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TripleStat extends StatelessWidget {
  final ImpactStats stats;
  const _TripleStat({required this.stats});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = stats.topPolymerCode;
    Widget div() =>
        Container(width: 1, height: 34, color: scheme.outlineVariant);
    return _Panel(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          Expanded(
              child: Center(
                  child: Metric(
                      label: 'Batches',
                      value: '${stats.scanCount}',
                      align: CrossAxisAlignment.center))),
          div(),
          Expanded(
              child: Center(
                  child: Metric(
                      label: 'Verified',
                      value: '${stats.scanCount}',
                      align: CrossAxisAlignment.center))),
          div(),
          Expanded(
            child: Center(
              child: Metric(
                label: 'Top resin',
                value: top == null ? '—' : PolymerCatalog.lookup(top).shortName,
                valueStyle: AppType.metricM,
                align: CrossAxisAlignment.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Equivalences extends StatelessWidget {
  final ImpactStats stats;
  const _Equivalences({required this.stats});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget div() =>
        Container(width: 1, height: 34, color: scheme.outlineVariant);
    return _Panel(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          Expanded(
              child: Center(
                  child: Metric(
                      label: 'Trees / yr',
                      value: stats.treesEquivalent.toStringAsFixed(1),
                      align: CrossAxisAlignment.center))),
          div(),
          Expanded(
              child: Center(
                  child: Metric(
                      label: 'Petrol',
                      value: Formatters.compact(stats.litresPetrolEquivalent),
                      unit: 'L',
                      align: CrossAxisAlignment.center))),
          div(),
          Expanded(
              child: Center(
                  child: Metric(
                      label: 'CO₂',
                      value: Formatters.compact(stats.totalCo2SavedKg),
                      unit: 'kg',
                      align: CrossAxisAlignment.center))),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.review),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatusTag(label: 'Sync', color: AppColors.review),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$count batch${count == 1 ? '' : 'es'} queued — uploads '
              'automatically when back online.',
              style: AppType.caption,
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
    final scheme = Theme.of(context).colorScheme;
    return _Panel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No batches yet',
              style: AppType.heading.copyWith(color: scheme.onSurface)),
          const SizedBox(height: 6),
          Text(
              'Place plastic on the scale, capture it, and PolyMint verifies the '
              'physical event before minting a credit.',
              style: AppType.body.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onScan, child: const Text('Scan first batch')),
        ],
      ),
    );
  }
}

class _GlobalExchange extends StatelessWidget {
  final ImpactStats stats;
  const _GlobalExchange({required this.stats});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget div() =>
        Container(width: 1, height: 34, color: scheme.outlineVariant);
    return _Panel(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          Expanded(
              child: Center(
                  child: Metric(
                      label: 'Credits',
                      value: Formatters.compact(stats.totalCredits),
                      align: CrossAxisAlignment.center))),
          div(),
          Expanded(
              child: Center(
                  child: Metric(
                      label: 'Recovered',
                      value: Formatters.compact(stats.totalWeightKg),
                      unit: 'kg',
                      align: CrossAxisAlignment.center))),
          div(),
          Expanded(
              child: Center(
                  child: Metric(
                      label: 'Batches',
                      value: '${stats.scanCount}',
                      align: CrossAxisAlignment.center))),
        ],
      ),
    );
  }
}
