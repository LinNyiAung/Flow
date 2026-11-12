import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/auth/register_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/app_logo.dart';
import 'package:frontend/widgets/mascot.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _pose(MascotPose pose) =>
    find.byWidgetPredicate((w) => w is Mascot && w.pose == pose, description: 'Mascot(${pose.name})');

/// A 390 × 844 phone (iPhone 12-15 class); [top] / [bottom] are its safe areas.
Future<void> _pump(WidgetTester tester, Widget home, {String lang = 'en', double width = 390, double height = 844}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>(
    create: (_) => AuthProvider(),
    child: MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('my')],
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final lang in ['en', 'my']) {
    final l = AppLocalizations(Locale(lang));

    group(lang, () {
      testWidgets('sign in: he waves above the form; logo and wordmark stay', (tester) async {
        await _pump(tester, const LoginScreen(), lang: lang);
        expect(_pose(MascotPose.waveHappy), findsOneWidget);
        expect(find.byType(AppLogo), findsOneWidget);
        expect(find.text(l.toePwar), findsOneWidget);
        final email = find.widgetWithText(TextFormField, l.emailLabel);
        expect(tester.getBottomLeft(_pose(MascotPose.waveHappy)).dy, lessThanOrEqualTo(tester.getTopLeft(email).dy));
      });

      testWidgets('sign in still fits a 390 × 844 phone without scrolling', (tester) async {
        await _pump(tester, const LoginScreen(), lang: lang);
        // Everything down to the "create an account" link is above the
        // bottom safe area (844 - 34).
        final signIn = find.widgetWithText(FilledButton, l.signIn);
        expect(tester.getBottomLeft(signIn).dy, lessThanOrEqualTo(810));
        expect(tester.getBottomLeft(find.byType(RichText).last).dy, lessThanOrEqualTo(810));
      });

      testWidgets('sign up: he waves above the form', (tester) async {
        await _pump(tester, RegisterScreen(), lang: lang);
        expect(_pose(MascotPose.waveHappy), findsOneWidget);
        final name = find.widgetWithText(TextFormField, l.fullNameLabel);
        expect(tester.getBottomLeft(_pose(MascotPose.waveHappy)).dy, lessThanOrEqualTo(tester.getTopLeft(name).dy));
      });

      testWidgets('sign up: the Create account button is no lower than before', (tester) async {
        await _pump(tester, RegisterScreen(), lang: lang);
        final create = find.widgetWithText(FilledButton, l.createAccountButton);
        // English fits above the bottom safe area (844 - 34), as before the
        // mascot. Myanmar (wider test font, more wrapping) already needed a
        // scroll before him (button bottom at 887): it must not get lower.
        expect(tester.getBottomLeft(create).dy, lessThanOrEqualTo(lang == 'en' ? 810 : 887));
      });

      testWidgets('360 px: sign in and sign up do not overflow', (tester) async {
        await _pump(tester, const LoginScreen(), lang: lang, width: 360, height: 640);
        expect(tester.takeException(), isNull);
        await _pump(tester, RegisterScreen(), lang: lang, width: 360, height: 640);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
