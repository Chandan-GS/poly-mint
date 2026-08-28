import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/preferences_service.dart';
import '../../../data/services/transaction_repository.dart';
import '../../auth/view/sign_in_screen.dart';
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
                const SectionLabel('Account'),
                const _AccountSection(),
                const SizedBox(height: 22),
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

/// Shows the signed-in Google account (with sign-out) or a sign-in prompt.
/// Rebuilds on auth changes so it reflects sign-in done elsewhere.
class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<User?>(
      stream: sl<AuthService>().authStateChanges(),
      builder: (context, snap) {
        final user = snap.data ?? sl<AuthService>().currentUser;
        if (user == null) {
          return Panel(
            padding: EdgeInsets.zero,
            child: KeyValueRow(
              label: 'Sign in with Google',
              value: const SizedBox.shrink(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SignInScreen(allowSkip: false)),
              ),
            ),
          );
        }
        return Panel(
          child: Row(
            children: [
              _Avatar(name: user.displayName ?? user.email ?? '?'),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.displayName ?? 'Signed in',
                        style: AppType.bodyStrong
                            .copyWith(color: scheme.onSurface)),
                    if (user.email != null)
                      Text(user.email!,
                          style: AppType.monoSmall
                              .copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () async {
                  await sl<AuthService>().signOut();
                  await sl<PreferencesService>().clearIdentity();
                },
                child: const Text('Sign out'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.onSurface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: AppType.bodyStrong.copyWith(color: scheme.surface)),
    );
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
