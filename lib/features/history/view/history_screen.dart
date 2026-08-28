import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../data/models/polymer_info.dart';
import '../../../data/services/preferences_service.dart';
import '../../../data/services/transaction_repository.dart';
import '../../dashboard/view/transaction_tile.dart';
import '../cubit/history_cubit.dart';

class HistoryScreen extends StatelessWidget {
  final VoidCallback onScanRequested;
  const HistoryScreen({super.key, required this.onScanRequested});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HistoryCubit(
        sl<TransactionRepository>(),
        sl<PreferencesService>().userId,
      ),
      child: _HistoryView(onScanRequested: onScanRequested),
    );
  }
}

class _HistoryView extends StatelessWidget {
  final VoidCallback onScanRequested;
  const _HistoryView({required this.onScanRequested});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log')),
      body: SafeArea(
        child: BlocBuilder<HistoryCubit, HistoryState>(
          builder: (context, state) {
            if (state.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.all.isEmpty) {
              return EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No batches yet',
                message:
                    'Once you scan and mint, every batch is logged here.',
                action: FilledButton(
                  onPressed: onScanRequested,
                  child: const Text('Scan a batch'),
                ),
              );
            }
            return Column(
              children: [
                _FilterBar(state: state),
                Expanded(
                  child: state.visible.isEmpty
                      ? Center(
                          child: Text('Nothing here.',
                              style: AppType.body.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          children: [
                            Panel(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  for (var i = 0;
                                      i < state.visible.length;
                                      i++) ...[
                                    if (i > 0) const RowDivider(),
                                    TransactionTile(txn: state.visible[i]),
                                  ]
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final HistoryState state;
  const _FilterBar({required this.state});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        children: [
          _Chip(
            label: 'All',
            selected: state.filter == null,
            onTap: () => context.read<HistoryCubit>().setFilter(null),
          ),
          for (final code in state.availableCodes)
            _Chip(
              label: PolymerCatalog.lookup(code).shortName,
              selected: state.filter == code,
              onTap: () => context.read<HistoryCubit>().setFilter(code),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? scheme.onSurface : scheme.surface,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: AppType.monoSmall.copyWith(
              color: selected ? scheme.surface : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
