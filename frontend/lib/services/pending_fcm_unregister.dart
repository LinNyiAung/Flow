import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A logout whose `DELETE /api/auth/fcm-token` did not go through (offline,
/// timeout, 5xx). Persisted so the device can still be unregistered for the
/// previous account later (next app start / before the next login
/// registers this device again).
class PendingFcmUnregister {
  static const String _key = 'pending_fcm_unregister';

  /// Auth token of the signed-out session (the DELETE authenticates as it).
  final String authToken;

  /// Id of the signed-out user, when known — a pending delete for the same
  /// user who signs in again is cancelled instead of sent.
  final String? userId;

  /// This device's FCM token at logout (informational).
  final String? fcmToken;

  const PendingFcmUnregister({
    required this.authToken,
    this.userId,
    this.fcmToken,
  });

  Map<String, dynamic> toJson() => {
        'auth_token': authToken,
        if (userId != null) 'user_id': userId,
        if (fcmToken != null) 'fcm_token': fcmToken,
      };

  static PendingFcmUnregister? fromJson(Object? json) {
    if (json is! Map) return null;
    final authToken = json['auth_token'];
    if (authToken is! String || authToken.isEmpty) return null;
    final userId = json['user_id'];
    final fcmToken = json['fcm_token'];
    return PendingFcmUnregister(
      authToken: authToken,
      userId: userId is String ? userId : null,
      fcmToken: fcmToken is String ? fcmToken : null,
    );
  }

  static Future<PendingFcmUnregister?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return fromJson(jsonDecode(raw));
    } on FormatException {
      await prefs.remove(_key);
      return null;
    }
  }

  static Future<void> save(PendingFcmUnregister pending) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(pending.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Clears the pending entry only if it belongs to [authToken] (a newer
  /// logout's entry is kept).
  static Future<void> clearIfAuthToken(String authToken) async {
    final pending = await load();
    if (pending != null && pending.authToken == authToken) await clear();
  }
}
