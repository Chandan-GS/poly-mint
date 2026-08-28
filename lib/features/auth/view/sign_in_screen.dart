import 'package:flutter/material.dart';

import '../../../core/di/injector.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/preferences_service.dart';
import '../../home/view/home_shell.dart';

/// Google sign-in. When [allowSkip] is true (first-run gate) the user may
/// continue without an account; when pushed from Config it's false.
class SignInScreen extends StatefulWidget {
  final bool allowSkip;
  const SignInScreen({super.key, this.allowSkip = true});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;

  Future<void> _google() async {
    setState(() => _busy = true);
    try {
      final user = await sl<AuthService>().signInWithGoogle();
      if (user == null) {
        if (mounted) setState(() => _busy = false);
        return; // cancelled
      }
      await sl<PreferencesService>().bindIdentity(
        uid: user.uid,
        name: user.displayName,
        photo: user.photoURL,
      );
      if (!mounted) return;
      // Gate-root: the auth stream swaps to Home automatically. Modal: pop back.
      if (Navigator.canPop(context)) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e.toString();
      final hint = (msg.contains('10') || msg.contains('DEVELOPER_ERROR'))
          ? 'Sign-in isn\'t configured yet — add this app\'s SHA-1 in Firebase.'
          : 'Sign-in failed. Please try again.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(hint)));
    }
  }

  Future<void> _skip() async {
    await sl<PreferencesService>().setAuthSkipped(true);
    if (!mounted) return;
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
              Text('Sign in',
                  style: AppType.screenTitle
                      .copyWith(fontSize: 30, color: scheme.onSurface)),
              const SizedBox(height: 14),
              Text(
                'Your account keeps your batches, credits and ranking in one '
                'place across devices.',
                style: AppType.body.copyWith(
                    color: scheme.onSurfaceVariant, fontSize: 15, height: 1.55),
              ),
              const Spacer(),
              _GoogleButton(busy: _busy, onPressed: _busy ? null : _google),
              if (widget.allowSkip) ...[
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : _skip,
                    child: Text('Continue without an account',
                        style: AppType.bodyStrong
                            .copyWith(color: scheme.onSurfaceVariant)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onPressed;
  const _GoogleButton({required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Simple mono "G" mark — no external asset needed.
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('G',
                        style: AppType.bodyStrong
                            .copyWith(color: AppColors.accent, fontSize: 13)),
                  ),
                  const SizedBox(width: 12),
                  Text('Continue with Google',
                      style: AppType.bodyStrong
                          .copyWith(color: scheme.onSurface)),
                ],
              ),
      ),
    );
  }
}
