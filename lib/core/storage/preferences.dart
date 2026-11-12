import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saves a text setting. A failure is only logged, because a setting that did not save is never worth an error.
Future<void> persistString(String key, String value) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  } catch (e) {
    debugPrint('Failed to persist "$key": $e');
  }
}

/// Saves a number setting, the same way as [persistString].
Future<void> persistDouble(String key, double value) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  } catch (e) {
    debugPrint('Failed to persist "$key": $e');
  }
}

/// Saves a yes-or-no setting, the same way as [persistString].
Future<void> persistBool(String key, bool value) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  } catch (e) {
    debugPrint('Failed to persist "$key": $e');
  }
}
