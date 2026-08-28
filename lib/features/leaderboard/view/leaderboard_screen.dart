import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/services/preferences_service.dart';
import '../../../data/services/transaction_repository.dart';
import '../cubit/leaderboard_cubit.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LeaderboardCubit(sl<TransactionRepository>()),
      child: const _LeaderboardView(),
    );
  }
}

class _LeaderboardView extends StatelessWidget {
  const _LeaderboardView();

  @override
  Widget build(BuildContext context) {
    final myId = sl<PreferencesService>().userId;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ranks')),
      body: SafeArea(
        child: BlocBuilder<LeaderboardCubit, LeaderboardState>(
          builder: (context, state) {
            if (state.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.entries.isEmpty) {
              return const EmptyState(
                icon: Icons.bar_chart_outlined,
                title: 'No rankings yet',
                message: 'Mint the first credits to top the exchange.',
              );
            }
            final me = state.entries.where((e) => e.userId == myId).firstOrNull;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text('Verified mass recovered · this month',
                    style: AppType.body
                        .copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 14),
                Panel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < state.entries.length; i++) ...[
                        if (i > 0) const RowDivider(),
                        _RankRow(
                            entry: state.entries[i],
                            isMe: state.entries[i].userId == myId),
                      ]
                    ],
                  ),
                ),
                if (me != null) ...[
                  const SizedBox(height: 14),
                  Panel(
                    background: scheme.onSurface,
                    border: scheme.onSurface,
                    padding: EdgeInsets.zero,
                    child: _RankRow(entry: me, isMe: true, inverted: true),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final bool isMe;
  final bool inverted;
  const _RankRow(
      {required this.entry, required this.isMe, this.inverted = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onColor = inverted ? scheme.surface : scheme.onSurface;
    final rankColor = inverted
        ? AppColors.accentDark
        : (entry.rank == 1
            ? AppColors.accent
            : entry.rank <= 3
                ? scheme.onSurface
                : scheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(entry.rank.toString().padLeft(2, '0'),
                style: AppType.monoBody.copyWith(color: rankColor)),
          ),
          Expanded(
            child: Text(
              isMe ? 'You · ${entry.userName}' : entry.userName,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyStrong.copyWith(
                  color: onColor, fontWeight: FontWeight.w600),
            ),
          ),
          Text('${Formatters.compact(entry.totalWeightKg)} kg',
              style: AppType.monoBody.copyWith(color: onColor)),
        ],
      ),
    );
  }
}
