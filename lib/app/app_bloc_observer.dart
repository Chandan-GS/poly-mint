import 'dart:developer' as dev;
import 'package:flutter_bloc/flutter_bloc.dart';

/// Lightweight observer that logs bloc transitions and errors during
/// development. Wire it up in [main] via `Bloc.observer`.
class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    dev.log('${bloc.runtimeType} error',
        error: error, stackTrace: stackTrace, name: 'bloc');
    super.onError(bloc, error, stackTrace);
  }

  @override
  void onChange(BlocBase bloc, Change change) {
    dev.log('${bloc.runtimeType}: ${change.nextState.runtimeType}',
        name: 'bloc');
    super.onChange(bloc, change);
  }
}
