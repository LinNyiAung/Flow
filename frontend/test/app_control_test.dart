import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart' show AuthWrapper;
import 'package:frontend/models/app_config.dart';
import 'package:frontend/providers/app_control_provider.dart';
import 'package:frontend/providers/app_version_provider.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/auth/register_screen.dart';
import 'package:frontend/screens/maintenance/maintenance_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppConfig _config({
  bool on = false,
  bool canEnter = true,
  String message = 'Back soon.',
  String? backBy,
  Map<String, String> paused = const {},
}) =>
    AppConfig.fromJson({
      'maintenance': {'on': on, 'message': message, 'back_by': backBy, 'can_enter': canEnter},
      'paused': paused,
      'announcement': null,
    });

/// Signed out, with no session to restore.
class _SignedOut extends AuthProvider {
  _SignedOut({this.checking = false});
  final bool checking;
  @override
  bool get isAuthenticated => false;
  @override
  bool get isAuthChecking => checking;
  @override
  Future<void> checkAuthStatus() async {}
}

Future<void> _pumpApp(
  WidgetTester tester,
  Widget home,
  AppControlProvider control, {
  String lang = 'en',
  bool authChecking = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _SignedOut(checking: authChecking)),
      ChangeNotifierProvider<AppVersionProvider>(create: (_) => AppVersionProvider()),
      ChangeNotifierProvider<AppControlProvider>.value(value: control),
    ],
    child: MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: const [Locale('en'), Locale('my')],
      home: home,
    ),
  ));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppConfig.fromJson', () {
    test('reads every field', () {
      final config = AppConfig.fromJson({
        'maintenance': {
          'on': true,
          'message': 'Down for upgrades.',
          'back_by': '2026-11-26T10:00:00+06:30',
          'can_enter': false,
        },
        'paused': {'chat': 'Chat is paused.', 'signups': 'Closed.'},
        'announcement': {
          'id': 'a1',
          'updated_at': '2026-11-25T01:00:00+00:00',
          'style': 'warning',
          'text': 'Heads up',
          'link_url': 'https://example.com',
          'link_label': 'Read',
        },
      });
      expect(config.maintenanceOn, isTrue);
      expect(config.maintenanceMessage, 'Down for upgrades.');
      expect(config.backBy!.toUtc(), DateTime.utc(2026, 11, 26, 3, 30));
      expect(config.canEnter, isFalse);
      expect(config.paused, {'chat': 'Chat is paused.', 'signups': 'Closed.'});
      final a = config.announcement!;
      expect([a.id, a.updatedAt, a.style, a.text, a.linkUrl, a.linkLabel],
          ['a1', '2026-11-25T01:00:00+00:00', 'warning', 'Heads up', 'https://example.com', 'Read']);
    });

    test('an announcement without a link has none', () {
      final config = AppConfig.fromJson({
        'announcement': {'id': 'a2', 'updated_at': 'x', 'style': 'info', 'text': 'Hi', 'link_url': null, 'link_label': ''},
      });
      expect(config.announcement!.linkUrl, isNull);
    });

    test('unknown keys are ignored', () {
      final config = AppConfig.fromJson({
        'maintenance': {'on': false, 'message': '', 'back_by': null, 'can_enter': true, 'extra': 1},
        'paused': <String, dynamic>{},
        'announcement': null,
        'whatever': [1, 2],
      });
      expect(config.maintenanceOn, isFalse);
      expect(config.paused, isEmpty);
    });

    test('missing fields read as open', () {
      final config = AppConfig.fromJson({});
      expect(config.maintenanceOn, isFalse);
      expect(config.canEnter, isTrue);
      expect(config.backBy, isNull);
      expect(config.paused, isEmpty);
      expect(config.announcement, isNull);
      expect(AppConfig.open.paused, isEmpty);
    });
  });

  group('AppControlProvider', () {
    test('refresh applies the config', () async {
      final control = AppControlProvider(
        fetcher: () async => _config(paused: {'chat': 'Chat is paused.'}),
      );
      expect(control.config.paused, isEmpty); // open until the first read
      await control.refresh();
      expect(control.isPaused('chat'), isTrue);
      expect(control.pausedMessage('chat'), 'Chat is paused.');
      expect(control.isPaused('voice'), isFalse);
      expect(control.pausedMessage('voice'), isNull);
      control.dispose();
    });

    test('a failed refresh keeps the last config', () async {
      var fail = false;
      final control = AppControlProvider(
        fetcher: () async {
          if (fail) throw ApiException('down');
          return _config(paused: {'chat': 'Paused.'});
        },
      );
      await control.refresh();
      fail = true;
      await control.refresh();
      expect(control.isPaused('chat'), isTrue);
      control.dispose();
    });

    test('a first failed read leaves nothing paused', () async {
      final control = AppControlProvider(fetcher: () async => throw ApiException('down'));
      await control.refresh();
      expect(control.config.paused, isEmpty);
      expect(control.blocked, isFalse);
      control.dispose();
    });

    test('blocked only when maintenance is on and the person is not a tester', () async {
      var config = _config(on: true, canEnter: false);
      final control = AppControlProvider(fetcher: () async => config);
      await control.refresh();
      expect(control.blocked, isTrue);
      config = _config(on: true, canEnter: true);
      await control.refresh();
      expect(control.blocked, isFalse);
      config = _config(on: false, canEnter: false);
      await control.refresh();
      expect(control.blocked, isFalse);
      control.dispose();
    });

    test('refreshes when the app comes back to the front', () async {
      var reads = 0;
      final control = AppControlProvider(fetcher: () async {
        reads++;
        return AppConfig.open;
      });
      await control.refresh();
      final before = reads;
      control.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(reads, before);
      control.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await control.refresh();
      expect(reads, greaterThan(before));
      control.dispose();
    });
  });

  group('ApiService', () {
    tearDown(() {
      ApiService.httpClientOverride = null;
      ApiService.onAppControlSignal = null;
    });

    test('getAppConfig asks for the Myanmar text as my, also for mm', () async {
      SharedPreferences.setMockInitialValues({});
      final urls = <Uri>[];
      ApiService.httpClientOverride = MockClient((request) async {
        urls.add(request.url);
        return http.Response(jsonEncode({'maintenance': {'on': false}, 'paused': {'chat': 'x'}}), 200);
      });
      final config = await ApiService.getAppConfig(lang: 'my');
      await ApiService.getAppConfig(lang: 'mm');
      await ApiService.getAppConfig(lang: 'en');
      expect(urls.map((u) => u.path).toSet(), {'/api/app/config'});
      expect(urls.map((u) => u.queryParameters['lang']), ['my', 'my', 'en']);
      expect(config.paused, {'chat': 'x'});
    });

    test('a paused feature or maintenance answer signals the app', () async {
      var signals = 0;
      ApiService.onAppControlSignal = () => signals++;
      ApiService.checkAppControlSignal(
          403, jsonEncode({'detail': {'code': 'feature_paused', 'feature': 'chat', 'message': 'm'}}));
      expect(signals, 1);
      ApiService.checkAppControlSignal(
          503, jsonEncode({'detail': {'code': 'maintenance', 'message': 'm', 'back_by': null}}));
      expect(signals, 2);
      // Other refusals do not.
      ApiService.checkAppControlSignal(403, jsonEncode({'detail': {'code': 'plan_feature_locked'}}));
      ApiService.checkAppControlSignal(503, 'Bad gateway');
      ApiService.checkAppControlSignal(
          500, jsonEncode({'detail': {'code': 'maintenance'}}));
      expect(signals, 2);
    });
  });

  group('MaintenanceScreen', () {
    testWidgets('shows the message and the back-by time in local time', (tester) async {
      final backBy = DateTime.utc(2026, 11, 26, 3, 30);
      final control = AppControlProvider(
        fetcher: () async => _config(
          on: true,
          canEnter: false,
          message: 'We are upgrading the servers.',
          backBy: backBy.toIso8601String(),
        ),
      );
      await control.refresh();
      await _pumpApp(tester, const MaintenanceScreen(), control);
      expect(find.text('Under maintenance'), findsOneWidget);
      expect(find.text('We are upgrading the servers.'), findsOneWidget);
      final local = backBy.toLocal();
      final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
      expect(find.textContaining('Back by 26 Nov 2026'.replaceFirst('26', '${local.day}')), findsOneWidget);
      expect(find.textContaining('$hour:${local.minute.toString().padLeft(2, '0')}'), findsOneWidget);
      control.dispose();
    });

    testWidgets('no back-by line when no time is set', (tester) async {
      final control = AppControlProvider(fetcher: () async => _config(on: true, canEnter: false));
      await control.refresh();
      await _pumpApp(tester, const MaintenanceScreen(), control);
      expect(find.textContaining('Back by'), findsNothing);
      control.dispose();
    });

    testWidgets('Retry reads the config again', (tester) async {
      var reads = 0;
      final control = AppControlProvider(fetcher: () async {
        reads++;
        return _config(on: true, canEnter: false);
      });
      await control.refresh();
      await _pumpApp(tester, const MaintenanceScreen(), control);
      final before = reads;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(reads, before + 1);
      control.dispose();
    });

    testWidgets('the Sign in link shows only when signed out', (tester) async {
      final control = AppControlProvider(fetcher: () async => _config(on: true, canEnter: false));
      await control.refresh();
      var taps = 0;
      await _pumpApp(tester, MaintenanceScreen(onSignIn: () => taps++), control);
      await tester.tap(find.text('Sign in'));
      expect(taps, 1);

      await _pumpApp(tester, const MaintenanceScreen(), control);
      expect(find.text('Sign in'), findsNothing);
      control.dispose();
    });

    testWidgets('is in Myanmar', (tester) async {
      final control = AppControlProvider(fetcher: () async => _config(on: true, canEnter: false));
      await control.refresh();
      await _pumpApp(tester, const MaintenanceScreen(), control, lang: 'my');
      expect(find.text(AppLocalizations(const Locale('my')).maintenanceTitle), findsOneWidget);
      expect(find.text('Under maintenance'), findsNothing);
      control.dispose();
    });
  });

  group('start-up gate', () {
    testWidgets('waits for the first read: spinner, then maintenance', (tester) async {
      final gate = Completer<AppConfig>();
      final control = AppControlProvider(fetcher: () => gate.future);
      await _pumpApp(tester, const AuthWrapper(), control);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(MaintenanceScreen), findsNothing);

      gate.complete(_config(on: true, canEnter: false));
      await tester.pump();
      await tester.pump();
      expect(find.byType(MaintenanceScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      control.dispose();
    });

    testWidgets('a read that never returns lets the app carry on after 10 s', (tester) async {
      final control = AppControlProvider(fetcher: () => Completer<AppConfig>().future);
      await _pumpApp(tester, const AuthWrapper(), control);
      await tester.pump(const Duration(seconds: 9));
      expect(find.byType(LoginScreen), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(control.blocked, isFalse);
      control.dispose();
    });

    testWidgets('no Sign in link while the saved session is being restored', (tester) async {
      final control = AppControlProvider(fetcher: () async => _config(on: true, canEnter: false));
      await control.refresh();
      await _pumpApp(tester, const AuthWrapper(), control, authChecking: true);
      expect(find.byType(MaintenanceScreen), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
      control.dispose();
    });

    testWidgets('maintenance shows before login; Sign in opens login, back returns', (tester) async {
      final control = AppControlProvider(
        fetcher: () async => _config(on: true, canEnter: false, message: 'Back soon.'),
      );
      await control.refresh();
      await _pumpApp(tester, const AuthWrapper(), control);
      expect(find.byType(MaintenanceScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);

      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();
      expect(find.byType(MaintenanceScreen), findsOneWidget);
      control.dispose();
    });

    testWidgets('a tester (can enter) or no maintenance goes straight to login', (tester) async {
      final control = AppControlProvider(fetcher: () async => _config(on: true, canEnter: true));
      await control.refresh();
      await _pumpApp(tester, const AuthWrapper(), control);
      expect(find.byType(MaintenanceScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      control.dispose();
    });
  });

  group('sign-ups closed', () {
    testWidgets('the register screen shows the message and disables Create', (tester) async {
      final control = AppControlProvider(
        fetcher: () async => _config(paused: {'signups': 'Sign-ups are paused for now.'}),
      );
      await control.refresh();
      await _pumpApp(tester, RegisterScreen(), control);
      expect(find.text('Sign-ups are paused for now.'), findsOneWidget);
      expect(find.text('Sign-ups are closed for now'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create account'));
      expect(button.onPressed, isNull);
      control.dispose();
    });

    testWidgets('the register screen is normal when sign-ups are open', (tester) async {
      final control = AppControlProvider(fetcher: () async => AppConfig.open);
      await control.refresh();
      await _pumpApp(tester, RegisterScreen(), control);
      expect(find.text('Sign-ups are closed for now'), findsNothing);
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create account'));
      expect(button.onPressed, isNotNull);
      control.dispose();
    });

    testWidgets('the login Register link shows the message instead of opening', (tester) async {
      final control = AppControlProvider(
        fetcher: () async => _config(paused: {'signups': 'Sign-ups are paused for now.'}),
      );
      await control.refresh();
      await _pumpApp(tester, const LoginScreen(embedded: true), control);
      await tester.ensureVisible(find.textContaining('Create an account', findRichText: true));
      await tester.tap(find.textContaining('Create an account', findRichText: true));
      await tester.pump();
      expect(find.text('Sign-ups are paused for now.'), findsOneWidget);
      expect(find.byType(RegisterScreen), findsNothing);
      control.dispose();
    });

    testWidgets('the login Register link opens the screen when sign-ups are open', (tester) async {
      final control = AppControlProvider(fetcher: () async => AppConfig.open);
      await control.refresh();
      await _pumpApp(tester, const LoginScreen(embedded: true), control);
      await tester.ensureVisible(find.textContaining('Create an account', findRichText: true));
      await tester.tap(find.textContaining('Create an account', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);
      control.dispose();
    });
  });
}
