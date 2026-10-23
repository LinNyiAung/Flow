import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/platform/platform_info.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/fcm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final deleteCalls = <String>[];

  setUp(() {
    deleteCalls.clear();
    ApiService.deleteFcmTokenOverride = (String authToken) async {
      deleteCalls.add(authToken);
    };
  });

  tearDown(() {
    PlatformInfo.isWeb = kIsWeb;
    ApiService.deleteFcmTokenOverride = null;
  });

  Future<AuthProvider> signedInProvider() async {
    SharedPreferences.setMockInitialValues({'access_token': 'old-token'});
    return AuthProvider();
  }

  test('logout on web does not unregister the FCM token', () async {
    PlatformInfo.isWeb = true;
    final auth = await signedInProvider();

    await auth.logout();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(deleteCalls, isEmpty);
    // The session itself is still ended.
    expect(await ApiService.getToken(), isNull);
  });

  test('logout on Android still unregisters', () async {
    PlatformInfo.isWeb = false;
    final auth = await signedInProvider();

    await auth.logout();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(deleteCalls, ['old-token']);
  });

  test('FCMService on web is inert', () async {
    PlatformInfo.isWeb = true;

    await FCMService().initialize();
    await FCMService().sendTokenToBackend();
    await FCMService().subscribeToTopic('t');
    await FCMService().unsubscribeFromTopic('t');

    expect(FCMService().fcmToken, isNull);
  });
}
