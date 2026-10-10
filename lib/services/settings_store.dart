import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/settings.dart';

/// Loads and saves [AppSettings] as one JSON value in shared_preferences.
class SettingsStore extends ChangeNotifier {
  SettingsStore([AppSettings initial = const AppSettings()]) : _value = initial;

  static const _key = 'settings';

  AppSettings _value;
  AppSettings get value => _value;

  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsStore(decode(prefs.getString(_key)));
  }

  /// Parses stored settings; a corrupt or missing value gives the defaults
  /// rather than a crash at startup.
  static AppSettings decode(String? raw) {
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } on Object {
      return const AppSettings();
    }
  }

  Future<void> update(AppSettings next) async {
    _value = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(next.toJson()));
  }
}
