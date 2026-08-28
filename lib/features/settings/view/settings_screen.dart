import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../data/services/transaction_repository.dart';
import '../../guide/view/resin_guide_screen.dart';
import '../cubit/settings_cubit.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Config')),
      body: SafeArea(
        child: BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, state) {
            final scheme = Theme.of(context).colorScheme;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                const SectionLabel('You'),
                Panel(
                  padding: EdgeInsets.zero,
                  child: KeyValueRow(
                    label: 'Display name',
                    value: Text(state.displayName,
                        style: AppType.monoBody
                            .copyWith(color: scheme.onSurfaceVariant)),
                    onTap: () => _editName(context, state.displayName),
                  ),
                ),
                const SizedBox(height: 22),

                // --- Sensor (the with/without-hardware switch) ---
                const SectionLabel('Sensor'),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Weight source', style: AppType.body),
                      const SizedBox(height: 10),
                      SegmentedToggle<String>(
                        options: const [
                          ('simulated', 'Simulated'),
                          ('ble', 'Sensor'),
                        ],
                        selected: state.sensorMode == 'ble'
                            ? 'ble'
                            : 'simulated',
                        onChanged: (m) =>
                            context.read<SettingsCubit>().setSensorMode(m),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        state.sensorMode == 'ble'
                            ? 'Connects to a PolyMint weight sensor over '
                                'Bluetooth when you scan.'
                            : 'No hardware needed — the app fills in a realistic '
                                'weight so you can try the full flow.',
                        style: AppType.caption
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                const SectionLabel('Detection'),
                Panel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SwitchRow(
                        label: 'Steadier reading',
                        sub: 'Uses a few frames and averages them.',
                        value: state.highAccuracyMode,
                        onChanged: (v) => context
                            .read<SettingsCubit>()
                            .setHighAccuracyMode(v),
                      ),
                      const RowDivider(),
                      KeyValueRow(
                        label: 'Only auto-verify above',
                        value: Text('85%',
                            style: AppType.monoBody
                                .copyWith(color: scheme.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                const SectionLabel('Appearance'),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Theme', style: AppType.body),
                      const SizedBox(height: 10),
                      SegmentedToggle<ThemeMode>(
                        options: const [
                          (ThemeMode.light, 'Light'),
                          (ThemeMode.system, 'Auto'),
                          (ThemeMode.dark, 'Dark'),
                        ],
                        selected: state.themeMode,
                        onChanged: (m) =>
                            context.read<SettingsCubit>().setThemeMode(m),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                const SectionLabel('More'),
                Panel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      KeyValueRow(
                        label: 'Resin guide',
                        value: const SizedBox.shrink(),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ResinGuideScreen()),
                        ),
                      ),
                      const RowDivider(),
                      const _SyncRow(),
                      const RowDivider(),
                      KeyValueRow(
                        label: 'Version',
                        value: Text('1.0.0',
                            style: AppType.monoBody
                                .copyWith(color: scheme.onSurfaceVariant)),
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

  Future<void> _editName(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final cubit = context.read<SettingsCubit>();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Your name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != null) cubit.setDisplayName(result);
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow(
      {required this.label,
      required this.sub,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppType.body),
                const SizedBox(height: 2),
                Text(sub,
                    style: AppType.caption
                        .copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeTrackColor: AppColors.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SyncRow extends StatefulWidget {
  const _SyncRow();
  @override
  State<_SyncRow> createState() => _SyncRowState();
}

class _SyncRowState extends State<_SyncRow> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = sl<TransactionRepository>().pendingCount;
    return KeyValueRow(
      label: 'Offline queue',
      value: _syncing
          ? const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : pending > 0
              ? TextButton(onPressed: _sync, child: Text('Sync $pending'))
              : Text('Synced',
                  style: AppType.monoBody
                      .copyWith(color: scheme.onSurfaceVariant)),
    );
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final synced = await sl<TransactionRepository>().flushQueue();
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(synced > 0
            ? 'Synced $synced batch${synced == 1 ? '' : 'es'}.'
            : 'Nothing synced — check your connection.'),
      ),
    );
  }
}
