import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ThemeModeStore {
  Future<String?> read();
  Future<void> write(String value);
}

final class SharedPreferencesThemeModeStore implements ThemeModeStore {
  SharedPreferencesThemeModeStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const preferenceKey = 'appearance_theme_mode';
  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read() => _preferences.getString(preferenceKey);

  @override
  Future<void> write(String value) =>
      _preferences.setString(preferenceKey, value);
}

ThemeMode themeModeFromStorage(String? value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  'system' => ThemeMode.system,
  _ => ThemeMode.system,
};
