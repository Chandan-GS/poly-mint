import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/di/injector.dart';
import '../core/theme/app_theme.dart';
import '../data/services/preferences_service.dart';
import '../features/auth/view/auth_gate.dart';
import '../features/onboarding/view/onboarding_screen.dart';
import '../features/settings/cubit/settings_cubit.dart';

class PolyMintApp extends StatelessWidget {
  const PolyMintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SettingsCubit(sl<PreferencesService>()),
      child: BlocBuilder<SettingsCubit, SettingsState>(
        buildWhen: (a, b) => a.themeMode != b.themeMode,
        builder: (context, settings) {
          return MaterialApp(
            title: 'PolyMint',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,
            home: const _RootGate(),
          );
        },
      ),
    );
  }
}

/// Decides the first screen: onboarding on first launch, then the auth gate.
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final prefs = sl<PreferencesService>();
    return prefs.hasOnboarded
        ? const AuthGate()
        : const OnboardingScreen();
  }
}
