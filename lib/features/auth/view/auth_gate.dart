import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/preferences_service.dart';
import '../../home/view/home_shell.dart';
import '../../settings/cubit/settings_cubit.dart';
import 'sign_in_screen.dart';

/// Routes on auth state: signed-in → app; skipped → app (anonymous);
/// otherwise → sign-in. Sits above [HomeShell] so signing out returns here.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: sl<AuthService>().authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        if (user != null) return _SignedIn(user: user);
        if (sl<PreferencesService>().authSkipped) return const HomeShell();
        return const SignInScreen();
      },
    );
  }
}

/// Binds the Firebase identity into prefs (so the rest of the app is keyed by
/// the real account) once, then shows the app.
class _SignedIn extends StatefulWidget {
  final User user;
  const _SignedIn({required this.user});

  @override
  State<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends State<_SignedIn> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await sl<PreferencesService>().bindIdentity(
        uid: widget.user.uid,
        name: widget.user.displayName,
        photo: widget.user.photoURL,
      );
      if (!mounted) return;
      final name = widget.user.displayName;
      if (name != null && name.trim().isNotEmpty) {
        context.read<SettingsCubit>().setDisplayName(name);
      }
    });
  }

  @override
  Widget build(BuildContext context) => const HomeShell();
}
