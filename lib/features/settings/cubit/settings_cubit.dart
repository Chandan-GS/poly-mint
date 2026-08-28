import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/services/preferences_service.dart';

class SettingsState extends Equatable {
  final ThemeMode themeMode;
  final String displayName;
  final bool highAccuracyMode;

  /// 'simulated' | 'ble' — chooses the weight-sensor implementation.
  final String sensorMode;

  const SettingsState({
    required this.themeMode,
    required this.displayName,
    required this.highAccuracyMode,
    required this.sensorMode,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    String? displayName,
    bool? highAccuracyMode,
    String? sensorMode,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      displayName: displayName ?? this.displayName,
      highAccuracyMode: highAccuracyMode ?? this.highAccuracyMode,
      sensorMode: sensorMode ?? this.sensorMode,
    );
  }

  @override
  List<Object?> get props =>
      [themeMode, displayName, highAccuracyMode, sensorMode];
}

/// Owns user-facing settings and persists every change immediately.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._prefs)
      : super(SettingsState(
          themeMode: _decodeTheme(_prefs.themeMode),
          displayName: _prefs.displayName,
          highAccuracyMode: _prefs.highAccuracyMode,
          sensorMode: _prefs.sensorMode,
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

  Future<void> setSensorMode(String mode) async {
    await _prefs.setSensorMode(mode);
    emit(state.copyWith(sensorMode: mode));
  }
}
