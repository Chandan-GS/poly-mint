import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../data/services/transaction_repository.dart';
import '../../guide/view/resin_guide_screen.dart';
import '../cubit/settings_cubit.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _ProfileHeader(name: state.displayName),
              const _SectionLabel('Detection'),
              SwitchListTile(
                secondary: const Icon(Icons.hdr_strong),
                title: const Text('High-accuracy mode'),
                subtitle: const Text(
                    'Captures multiple frames and averages them for a steadier '
                    'prediction (slightly slower).'),
                value: state.highAccuracyMode,
                onChanged: (v) =>
                    context.read<SettingsCubit>().setHighAccuracyMode(v),
              ),
              const _SectionLabel('Appearance'),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Theme'),
                subtitle: Text(_themeLabel(state.themeMode)),
                trailing: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.light, icon: Icon(Icons.light_mode)),
                    ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto)),
                    ButtonSegment(
                        value: ThemeMode.dark, icon: Icon(Icons.dark_mode)),
                  ],
                  selected: {state.themeMode},
                  onSelectionChanged: (s) =>
                      context.read<SettingsCubit>().setThemeMode(s.first),
                ),
              ),
              const _SectionLabel('Learn'),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Recycling guide'),
                subtitle: const Text('Identify & prep every resin code'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ResinGuideScreen()),
                ),
              ),
              const _SectionLabel('Sync'),
              const _SyncTile(),
              const _SectionLabel('About'),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('PolyMint'),
                subtitle: Text(
                    'AI-verified plastic recovery & circular-economy credits.'),
                trailing: Text('v1.0.0'),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'Match system',
      };
}

class _ProfileHeader extends StatelessWidget {
  final String name;
  const _ProfileHeader({required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                Text('Contributor',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton.filledTonal(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () => _editName(context, name),
          ),
        ],
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

class _SyncTile extends StatefulWidget {
  const _SyncTile();

  @override
  State<_SyncTile> createState() => _SyncTileState();
}

class _SyncTileState extends State<_SyncTile> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final repo = sl<TransactionRepository>();
    final pending = repo.pendingCount;
    return ListTile(
      leading: const Icon(Icons.cloud_sync_outlined),
      title: const Text('Offline queue'),
      subtitle: Text(pending == 0
          ? 'Everything is synced'
          : '$pending batch${pending == 1 ? '' : 'es'} waiting to upload'),
      trailing: _syncing
          ? const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : (pending > 0
              ? TextButton(onPressed: _sync, child: const Text('Sync now'))
              : const Icon(Icons.check_circle, color: Color(0xFF16A34A))),
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}
