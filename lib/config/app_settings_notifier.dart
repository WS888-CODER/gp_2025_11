// lib/config/app_settings_notifier.dart
import 'package:flutter/material.dart';

class AppSettingsNotifier extends ChangeNotifier {
  // --- إدارة الثيم (Theme) ---
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  void toggleTheme(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners(); 
    }
  }

  // --- إدارة اللغة (Language) ---
  // نستخدم Locale('en') و Locale('ar') فقط
  Locale _locale = const Locale('en'); // الافتراضي English

  Locale get locale => _locale;
  String get currentLanguageName => _locale.languageCode == 'ar' ? 'Arabic' : 'English';

  void toggleLanguage() {
    _locale = _locale.languageCode == 'ar' 
        ? const Locale('en')
        : const Locale('ar');
    notifyListeners(); 
  }
}