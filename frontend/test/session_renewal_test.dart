import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/platform/platform_info.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/fcm_service.dart';
import 'package:frontend/utils/jwt_claims.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A JWT-shaped token (unsigned) whose payload carries [issuedAt] as `iat`.
/// [tag] keeps tokens of different tests apart.
String tokenIssuedAt(DateTime issuedAt, {required String tag}) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}'
      '.${part({'uid': 'u1', 'iat': issuedAt.millisecondsSinceEpoch ~/ 1000, 'tag': tag})}'
      '.signature';
}

const _userJson = {
  'id': 'u1',
  'name': 'Test',
  'email': 'test@example.com',
  'created_at': '2026-01-01T00:00:00Z',
  'is_verified': true,
};

/// Lets the app's async steps (SharedPreferences, the fake server) run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Every request the fake server saw: "METHOD path" and its bearer token.
  late List<String> requests;
  late List<String?> bearers;

  /// The answer to `POST /api/auth/renew-session`.
  late Future<http.Response> Function() renewAnswer;

  setUp(() {
    PlatformInfo.isWeb = false;
    requests = [];
    bearers = [];
    renewAnswer = () async => http.Response(
          jsonEncode({'access_token': 'renewed-token', 'token_type': 'bearer'}),
          200,
        );
    ApiService.httpClientOverride = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      bearers.add(request.headers['Authorization']);
      switch (request.url.path) {
        case '/api/auth/me':
          return http.Response(jsonEncode(_userJson), 200);
        case '/api/auth/renew-session':
          return renewAnswer();
        default:
          return http.Response('{}', 200);
      }
    });
    FCMService().setTokenForTest('push-1');
  });

  tearDown(() {
    PlatformInfo.isWeb = kIsWeb;
    ApiService.httpClientOverride = null;
    ApiService.onSessionExpired = null;
    FCMService().setTokenForTest(null);
  });

  int renewCalls() =>
      requests.where((r) => r == 'POST /api/auth/renew-session').length;

  /// Signs in by restoring a stored session whose token is [token].
  Future<AuthProvider> restore(String token) async {
    SharedPreferences.setMockInitialValues({'access_token': token});
    final auth = AuthProvider();
    await auth.checkAuthStatus();
    expect(auth.isAuthenticated, isTrue);
    return auth;
  }

  group('jwtIssuedAt', () {
    test('jwtIssuedAt reads iat', () {
      final issued = DateTime.utc(2026, 11, 1, 8, 30);
      expect(jwtIssuedAt(tokenIssuedAt(issued, tag: 'iat')), issued);
    });

    test('returns null for garbage', () {
      String withPayload(Object payload) =>
          'x.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.y';
      expect(jwtIssuedAt(''), isNull);
      expect(jwtIssuedAt('garbage'), isNull);
      expect(jwtIssuedAt('a.b.c'), isNull);
      expect(jwtIssuedAt('a.%%%.c'), isNull);
      expect(jwtIssuedAt(withPayload({'uid': 'u1'})), isNull);
      expect(jwtIssuedAt(withPayload({'iat': 'yesterday'})), isNull);
      expect(jwtIssuedAt(withPayload([1, 2])), isNull);
    });
  });

  test('renews when token is older than a day', () async {
    final old = tokenIssuedAt(DateTime.now().subtract(const Duration(days: 2)), tag: 'old');
    final auth = await restore(old);
    await settle();

    expect(renewCalls(), 1);
    expect(bearers[requests.indexOf('POST /api/auth/renew-session')], 'Bearer $old');
    expect(await ApiService.getToken(), 'renewed-token');
    expect(auth.isAuthenticated, isTrue);
    // The device is registered once, with the renewed token (its row then
    // follows the new expiry).
    final registrations = [
      for (var i = 0; i < requests.length; i++)
        if (requests[i] == 'POST /api/auth/update-fcm-token') bearers[i],
    ];
    expect(registrations, ['Bearer renewed-token']);

    // Fresh now: a resume does not renew again.
    await auth.renewSessionIfDue();
    await settle();
    expect(renewCalls(), 1);
  });

  test('no renewal when token is fresh', () async {
    final fresh = tokenIssuedAt(DateTime.now().subtract(const Duration(hours: 23)), tag: 'fresh');
    final auth = await restore(fresh);
    await settle();
    await auth.renewSessionIfDue();
    await settle();

    expect(renewCalls(), 0);
    expect(await ApiService.getToken(), fresh);
    // The device is still registered on restore.
    expect(requests, contains('POST /api/auth/update-fcm-token'));
  });

  test('late renewal after logout is dropped', () async {
    final answer = Completer<http.Response>();
    final asked = Completer<void>();
    renewAnswer = () {
      asked.complete();
      return answer.future;
    };
    final old = tokenIssuedAt(DateTime.now().subtract(const Duration(days: 3)), tag: 'late');
    final auth = await restore(old);
    await asked.future;

    await auth.logout();
    answer.complete(http.Response(
      jsonEncode({'access_token': 'late-token', 'token_type': 'bearer'}),
      200,
    ));
    await settle();

    expect(await ApiService.getToken(), isNull);
    expect(auth.isAuthenticated, isFalse);
    expect(bearers, isNot(contains('Bearer late-token')));
    // The signed-out device is not registered again by the late restore.
    expect(requests, isNot(contains('POST /api/auth/update-fcm-token')));
  });

  test('replaceTokenIfMatches stores only over the same token, unless cancelled', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'a'});

    expect(await ApiService.replaceTokenIfMatches('other', 'b'), isFalse);
    expect(await ApiService.getToken(), 'a');

    expect(await ApiService.replaceTokenIfMatches('a', 'b', cancelled: () => true), isFalse);
    expect(await ApiService.getToken(), 'a');

    expect(await ApiService.replaceTokenIfMatches('a', 'b', cancelled: () => false), isTrue);
    expect(await ApiService.getToken(), 'b');
  });

  test('server error keeps the token', () async {
    renewAnswer = () async => http.Response('{"detail": "down"}', 503);
    final old = tokenIssuedAt(DateTime.now().subtract(const Duration(days: 2)), tag: '503');
    final auth = await restore(old);
    await settle();

    expect(renewCalls(), 1);
    expect(await ApiService.getToken(), old);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.sessionRestoreFailed, isFalse);

    // The next resume tries again, and this time it works.
    renewAnswer = () async => http.Response(
          jsonEncode({'access_token': 'second-try', 'token_type': 'bearer'}),
          200,
        );
    await auth.renewSessionIfDue();
    expect(renewCalls(), 2);
    expect(await ApiService.getToken(), 'second-try');
  });

  test('a 401 takes the usual session-expired path', () async {
    renewAnswer = () async => http.Response('{"detail": "Could not validate credentials"}', 401);
    final old = tokenIssuedAt(DateTime.now().subtract(const Duration(days: 2)), tag: '401');
    SharedPreferences.setMockInitialValues({'access_token': old});
    final auth = AuthProvider();
    final expired = <String>[];
    ApiService.onSessionExpired = (token) {
      expired.add(token);
      auth.handleSessionExpired(token);
    };
    await auth.checkAuthStatus();
    await settle();

    expect(expired, [old]);
    expect(await ApiService.getToken(), isNull);
    expect(auth.isAuthenticated, isFalse);
  });
}
