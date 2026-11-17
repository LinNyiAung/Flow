import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/notification.dart';
import 'package:frontend/platform/platform_info.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/fcm_service.dart';
import 'package:frontend/services/pending_fcm_unregister.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userJson = {
  'id': 'u1',
  'name': 'Test',
  'email': 'test@example.com',
  'created_at': '2026-01-01T00:00:00Z',
  'is_verified': true,
};

/// Lets the app's async steps (SharedPreferences, the fake server) run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

/// A request the fake server saw.
class _Seen {
  _Seen(this.method, this.path, this.bearer, this.body);
  final String method;
  final String path;
  final String? bearer;
  final Object? body;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<_Seen> seen;

  /// `(authToken, fcmToken)` of every DELETE made through the test seam.
  late List<(String, String)> deleteCalls;

  List<_Seen> requestsTo(String path) => seen.where((r) => r.path == path).toList();

  setUp(() {
    PlatformInfo.isWeb = false;
    seen = [];
    deleteCalls = [];
    ApiService.httpClientOverride = MockClient((request) async {
      seen.add(_Seen(
        request.method,
        request.url.path,
        request.headers['Authorization'],
        request.body.isEmpty ? null : jsonDecode(request.body),
      ));
      switch (request.url.path) {
        case '/api/auth/me':
          return http.Response(jsonEncode(_userJson), 200);
        case '/api/auth/change-password':
          return http.Response(
            jsonEncode({'message': 'ok', 'access_token': 'after-change', 'token_type': 'bearer'}),
            200,
          );
        default:
          return http.Response('{}', 200);
      }
    });
  });

  tearDown(() {
    PlatformInfo.isWeb = kIsWeb;
    ApiService.httpClientOverride = null;
    ApiService.deleteFcmTokenOverride = null;
    FCMService().setTokenForTest(null);
  });

  void recordDeletes() {
    ApiService.deleteFcmTokenOverride = (String authToken, String fcmToken) async {
      deleteCalls.add((authToken, fcmToken));
    };
  }

  test('fcm previous token', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'auth-1'});
    FCMService().setTokenForTest('t1');

    await FCMService().sendTokenToBackend();
    await FCMService().handleTokenRefreshForTest('t2');

    final bodies = [for (final r in requestsTo('/api/auth/update-fcm-token')) r.body];
    expect(bodies, [
      {'fcm_token': 't1'},
      {'fcm_token': 't2', 'previous_token': 't1'},
    ]);
    expect(FCMService().fcmToken, 't2');

    // Registering the same token again names no previous token.
    await FCMService().sendTokenToBackend();
    expect(requestsTo('/api/auth/update-fcm-token').last.body, {'fcm_token': 't2'});
  });

  test('a token refreshed while the app was closed is sent with the old one', () async {
    // The last run registered t1; Firebase hands out t2 on this start.
    SharedPreferences.setMockInitialValues({
      'access_token': 'auth-1',
      'fcm_last_registered_token': 't1',
    });
    FCMService().setTokenForTest('t2');

    await FCMService().sendTokenToBackend();

    expect(requestsTo('/api/auth/update-fcm-token').single.body,
        {'fcm_token': 't2', 'previous_token': 't1'});
  });

  test('a failed registration keeps the previous token for the next try', () async {
    SharedPreferences.setMockInitialValues({
      'access_token': 'auth-1',
      'fcm_last_registered_token': 't1',
    });
    var fail = true;
    ApiService.httpClientOverride = MockClient((request) async {
      seen.add(_Seen(request.method, request.url.path, null, jsonDecode(request.body)));
      return fail ? http.Response('{"detail": "down"}', 503) : http.Response('{}', 200);
    });
    FCMService().setTokenForTest('t2');

    await FCMService().sendTokenToBackend();
    fail = false;
    await FCMService().sendTokenToBackend();

    expect([for (final r in seen) r.body], [
      {'fcm_token': 't2', 'previous_token': 't1'},
      {'fcm_token': 't2', 'previous_token': 't1'},
    ]);
  });

  test('logout sends this device\'s push token in the DELETE body', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'auth-1'});
    FCMService().setTokenForTest('push-1');
    final auth = AuthProvider();

    await auth.logout();
    await settle();

    final delete = requestsTo('/api/auth/fcm-token').single;
    expect(delete.method, 'DELETE');
    expect(delete.bearer, 'Bearer auth-1');
    expect(delete.body, {'fcm_token': 'push-1'});
    expect(await PendingFcmUnregister.load(), isNull);
  });

  test('logout without a push token makes no DELETE and saves no pending retry', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'auth-1'});
    recordDeletes();
    final auth = AuthProvider();

    await auth.logout();
    await settle();

    expect(deleteCalls, isEmpty);
    expect(requestsTo('/api/auth/fcm-token'), isEmpty);
    expect(await PendingFcmUnregister.load(), isNull);
    expect(await ApiService.getToken(), isNull);
  });

  test('pending retry sends the stored push token', () async {
    SharedPreferences.setMockInitialValues({
      'pending_fcm_unregister': jsonEncode(
        const PendingFcmUnregister(authToken: 'a1', userId: 'u9', fcmToken: 'f1').toJson(),
      ),
    });
    recordDeletes();
    final auth = AuthProvider();

    await auth.checkAuthStatus();
    await settle();

    expect(deleteCalls, [('a1', 'f1')]);
    expect(await PendingFcmUnregister.load(), isNull);
  });

  test('pending entry without a push token is cleared', () async {
    // Saved by the previous app version, which did not need the push token.
    SharedPreferences.setMockInitialValues({
      'pending_fcm_unregister': jsonEncode({'auth_token': 'a1', 'user_id': 'u9'}),
    });
    recordDeletes();
    final auth = AuthProvider();

    await auth.checkAuthStatus();
    await settle();

    expect(deleteCalls, isEmpty);
    expect(await PendingFcmUnregister.load(), isNull);
  });

  test('change password keeps this device and registers it again', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'auth-1'});
    FCMService().setTokenForTest('push-1');
    final auth = AuthProvider();
    await auth.checkAuthStatus();
    await settle();
    seen.clear();

    final ok = await auth.changePassword(
      currentPassword: 'old-pass',
      newPassword: 'new-pass',
      confirmPassword: 'new-pass',
    );
    await settle();

    expect(ok, isTrue);
    expect(requestsTo('/api/auth/change-password').single.body, {
      'current_password': 'old-pass',
      'new_password': 'new-pass',
      'confirm_password': 'new-pass',
      'fcm_token': 'push-1',
    });
    expect(await ApiService.getToken(), 'after-change');
    final registration = requestsTo('/api/auth/update-fcm-token').single;
    expect(registration.bearer, 'Bearer after-change');
    expect(registration.body, {'fcm_token': 'push-1'});
  });

  test('sign_in_reminder opens nothing', () {
    expect(notificationOpensSomething('sign_in_reminder'), isFalse);
  });
}
