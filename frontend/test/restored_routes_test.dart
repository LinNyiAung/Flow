import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/navigation/restored_routes.dart';
import 'package:frontend/platform/platform_info.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/screens/notifications/notifications_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userJson = {
  'id': 'u1',
  'name': 'Test',
  'email': 'test@example.com',
  'created_at': '2026-01-01T00:00:00Z',
  'is_verified': true,
};

const _notice = {
  'id': 'n1',
  'user_id': 'u1',
  'type': 'budget_now_active',
  'title': 'Budget started',
  'message': 'Your November budget is active',
  'subject_id': null,
  'goal_name': null,
  'currency': null,
  'created_at': '2026-11-19T08:00:00Z',
  'is_read': true,
  'extra': null,
};

/// The app's home route stand-in: like AuthWrapper, it restores the saved
/// session after its first frame.
class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (!auth.isAuthenticated) auth.checkAuthStatus();
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('home'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> requests;
  late http.Response Function() me;

  setUp(() {
    PlatformInfo.isWeb = true;
    requests = [];
    me = () => http.Response(jsonEncode(_userJson), 200);
    ApiService.httpClientOverride = MockClient((request) async {
      requests.add(request.url.path);
      switch (request.url.path) {
        case '/api/auth/me':
          return me();
        case '/api/notifications':
          return http.Response(jsonEncode([_notice]), 200);
        case '/api/notifications/unread-count':
          return http.Response(jsonEncode({'unread_count': 0}), 200);
        default:
          return http.Response('{}', 200);
      }
    });
  });

  tearDown(() {
    PlatformInfo.isWeb = kIsWeb;
    ApiService.httpClientOverride = null;
  });

  /// The app started on [route], as a browser reload of that page does.
  Future<void> reloadOn(WidgetTester tester, String route) async {
    final auth = AuthProvider();
    final notifications = NotificationProvider();
    // As in the app: a session restored for a user resets every per-user store.
    auth.onSessionReset = notifications.reset;
    final routes = <String, WidgetBuilder>{
      '/': (_) => const _Home(),
      '/notifications': (_) => NotificationsScreen(),
      '/privacy-policy': (_) => const Scaffold(body: Text('privacy')),
    };
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: notifications),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        initialRoute: route,
        routes: routes,
        onGenerateInitialRoutes: (name) => restoredInitialRoutes(
          name,
          pageFor: (n) => routes[n],
          public: const {'/privacy-policy'},
        ),
      ),
    ));
  }

  testWidgets('a reload on the notifications page shows them once the sign-in is restored', (tester) async {
    SharedPreferences.setMockInitialValues({'access_token': 'auth-1'});
    await reloadOn(tester, '/notifications');
    await tester.pumpAndSettle();

    expect(find.text('Budget started'), findsOneWidget);
    expect(requests.indexOf('/api/notifications'), greaterThan(requests.indexOf('/api/auth/me')),
        reason: 'the page loads only after the session restore (which resets the per-user stores)');
  });

  testWidgets('signed out: a reloaded page steps aside for the home route (sign-in)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await reloadOn(tester, '/notifications');
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(requests, isNot(contains('/api/notifications')));
  });

  testWidgets('the session cannot be restored (server down): the page steps aside for the retry', (tester) async {
    SharedPreferences.setMockInitialValues({'access_token': 'auth-1'});
    me = () => http.Response('{"detail": "down"}', 503);
    await reloadOn(tester, '/notifications');
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a public page opens at once, signed in or not', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await reloadOn(tester, '/privacy-policy');
    await tester.pumpAndSettle();

    expect(find.text('privacy'), findsOneWidget);
  });

  testWidgets('an unknown page starts on the home route alone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await reloadOn(tester, '/no-such-page');
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });
}
