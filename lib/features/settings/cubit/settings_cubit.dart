import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/services/preferences_service.dart';

class SettingsState extends Equatable {
  final ThemeMode themeMode;
  final String displayName;
  final bool highAccuracyMode;

  const SettingsState({
    required this.themeMode,
    required this.displayName,
    required this.highAccuracyMode,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    String? displayName,
    bool? highAccuracyMode,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      displayName: displayName ?? this.displayName,
      highAccuracyMode: highAccuracyMode ?? this.highAccuracyMode,
    );
  }

  @override
  List<Object?> get props => [themeMode, displayName, highAccuracyMode];
}

/// Owns user-facing settings and persists every change immediately.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._prefs)
      : super(SettingsState(
          themeMode: _decodeTheme(_prefs.themeMode),
          displayName: _prefs.displayName,
          highAccuracyMode: _prefs.highAccuracyMode,
        ));

  final PreferencesService _prefs;

  static ThemeMode _decodeTheme(String raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _encodeTheme(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setThemeMode(_encodeTheme(mode));
    emit(state.copyWith(themeMode: mode));
  }

  Future<void> setDisplayName(String name) async {
    final trimmed = name.trim().isEmpty ? 'Eco Contributor' : name.trim();
    await _prefs.setDisplayName(trimmed);
    emit(state.copyWith(displayName: trimmed));
  }

  Future<void> setHighAccuracyMode(bool value) async {
    await _prefs.setHighAccuracyMode(value);
    emit(state.copyWith(highAccuracyMode: value));
  }
}
