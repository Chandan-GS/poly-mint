import 'package:flutter/material.dart';

import '../../../core/di/injector.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../data/services/preferences_service.dart';
import '../../home/view/home_shell.dart';

/// First-launch screen. Plain language, editorial layout — states the one idea
/// (proof, not paperwork) and gets out of the way.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  Future<void> _finish(BuildContext context) async {
    await sl<PreferencesService>().setOnboarded();
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('◆ POLYMINT',
                  style: AppType.label
                      .copyWith(color: scheme.onSurface, letterSpacing: 2.5)),
              const SizedBox(height: 64),
              Text('Recycling you\ncan actually prove.',
                  style: AppType.screenTitle.copyWith(
                      fontSize: 30, height: 1.2, color: scheme.onSurface)),
              const SizedBox(height: 16),
              Text(
                'Put the plastic on the scale and take a photo. PolyMint checks '
                'that the weight and the photo happened together — so a picture '
                'off a screen or a made-up weight can\'t earn a credit.',
                style: AppType.body.copyWith(
                    color: scheme.onSurfaceVariant, fontSize: 15, height: 1.55),
              ),
              const SizedBox(height: 28),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('THE IDEA',
                        style: AppType.label
                            .copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Text.rich(TextSpan(
                      style: AppType.body.copyWith(color: scheme.onSurface),
                      children: const [
                        TextSpan(text: 'Others trust the paperwork.\n'),
                        TextSpan(
                            text: 'PolyMint checks the real thing.',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    )),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => _finish(context),
                child: const Text('Get started'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
