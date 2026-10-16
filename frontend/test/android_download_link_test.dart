import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/platform/platform_info.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/android_download_link.dart';
import 'package:provider/provider.dart';

const _desktopChrome =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const _androidChrome =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
const _iPhoneSafari =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const _iPad =
    'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

void main() {
  final originalIsWeb = PlatformInfo.isWeb;
  tearDown(() => PlatformInfo.isWeb = originalIsWeb);

  group('shouldOfferAndroidDownload', () {
    test('offers the link on a desktop browser', () {
      expect(
        shouldOfferAndroidDownload(isWeb: true, userAgent: _desktopChrome),
        isTrue,
      );
    });

    test('offers the link on an Android browser', () {
      expect(
        shouldOfferAndroidDownload(isWeb: true, userAgent: _androidChrome),
        isTrue,
      );
    });

    test('hides the link on iPhone', () {
      expect(
        shouldOfferAndroidDownload(isWeb: true, userAgent: _iPhoneSafari),
        isFalse,
      );
    });

    test('hides the link on iPad', () {
      expect(
        shouldOfferAndroidDownload(isWeb: true, userAgent: _iPad),
        isFalse,
      );
    });

    test('hides the link inside the Android app (not web)', () {
      for (final ua in [_desktopChrome, _androidChrome, _iPhoneSafari, '']) {
        expect(shouldOfferAndroidDownload(isWeb: false, userAgent: ua), isFalse);
      }
    });
  });

  testWidgets('renders nothing when not running on the web', (tester) async {
    PlatformInfo.isWeb = false;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AndroidDownloadLink())),
    );
    await tester.pump();

    final link = find.byType(AndroidDownloadLink);
    expect(tester.getSize(link), Size.zero);
    expect(find.descendant(of: link, matching: find.byType(InkWell)), findsNothing);
    expect(find.descendant(of: link, matching: find.byType(Text)), findsNothing);
    expect(find.text('Get the Android app'), findsNothing);
  });

  testWidgets('login screen adds no spacing for the link off the web',
      (tester) async {
    PlatformInfo.isWeb = false;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(
          localizationsDelegates: [AppLocalizations.delegate],
          supportedLocales: [Locale('en'), Locale('my')],
          home: LoginScreen(embedded: true),
        ),
      ),
    );
    await tester.pump();

    final link = find.byType(AndroidDownloadLink);
    expect(link, findsOneWidget);
    expect(tester.getSize(link), Size.zero);

    // The link is the Column's last child, directly after the register link,
    // with no spacer from this feature in between.
    final column = tester.widget<Column>(
      find.ancestor(of: link, matching: find.byType(Column)).first,
    );
    expect(column.children.last, isA<AndroidDownloadLink>());
    expect(column.children[column.children.length - 2], isA<GestureDetector>());
  });
}