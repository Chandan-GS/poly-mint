import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
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
      appBar: AppBar(title: const Text('History')),
      body: BlocBuilder<HistoryCubit, HistoryState>(
        builder: (context, state) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.all.isEmpty) {
            return EmptyState(
              icon: Icons.history,
              title: 'No batches yet',
              message: 'Once you scan and mint, your recovery history shows up '
                  'here.',
              action: FilledButton.icon(
                onPressed: onScanRequested,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Scan a batch'),
              ),
            );
          }
          return Column(
            children: [
              _FilterBar(state: state),
              Expanded(
                child: state.visible.isEmpty
                    ? const Center(child: Text('No batches for this filter'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          for (final t in state.visible)
                            TransactionTile(txn: t),
                        ],
                      ),
              ),
            ],
          );
        },
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
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: state.filter == null,
              onSelected: (_) => context.read<HistoryCubit>().setFilter(null),
            ),
          ),
          for (final code in state.availableCodes)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(PolymerCatalog.lookup(code).shortName),
                selected: state.filter == code,
                onSelected: (_) =>
                    context.read<HistoryCubit>().setFilter(code),
              ),
            ),
        ],
      ),
    );
  }
}
