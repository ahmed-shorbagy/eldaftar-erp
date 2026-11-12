import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../application/close_count_drafts.dart';

/// Keeps the close-count draft on this device. Storage failures are silent:
/// the counts still live in the open form, they are just not kept.
final class SharedPreferencesCloseCountDrafts implements CloseCountDrafts {
  const SharedPreferencesCloseCountDrafts();

  @override
  Future<Map<String, String>?> read(DraftScope scope) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(scope.storageKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(DraftScope scope, Map<String, String> fields) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (fields.isEmpty) {
        await preferences.remove(scope.storageKey);
      } else {
        await preferences.setString(scope.storageKey, jsonEncode(fields));
      }
    } catch (_) {
      // The draft is a convenience; the open form still holds the counts.
    }
  }

  @override
  Future<void> clear(DraftScope scope) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(scope.storageKey);
    } catch (_) {}
  }
}
