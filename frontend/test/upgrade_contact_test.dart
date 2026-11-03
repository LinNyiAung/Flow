import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/subscription/subscription_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/contact_details.dart';
import 'package:frontend/widgets/owner_contact_block.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An [AuthProvider] with a signed-in user, so the screen knows the account email.
class _SignedInAuth extends AuthProvider {
  _SignedInAuth(String email)
      : _signedIn = User(id: 'u1', name: 'Test', email: email, createdAt: DateTime.utc(2026, 1, 1));
  final User _signedIn;

  @override
  User? get user => _signedIn;
}

PlanStatus _status({
  OwnerContact owner = const OwnerContact(email: 'owner@example.com', viber: '+959123456789'),
  UpgradeRequest? upgradeRequest,
}) =>
    PlanStatus(
      plan: Plan.free,
      catalog: const {
        Plan.free: {PlanFeature.chat: CatalogLimit(mode: 'counted', quota: 7, period: 'week')},
        Plan.plus: {PlanFeature.chat: CatalogLimit(mode: 'counted', quota: 123, period: 'month')},
        Plan.pro: {PlanFeature.chat: CatalogLimit(mode: 'counted', quota: 456, period: 'month')},
      },
      upgradeContact: const {'en': 'Message us on Viber', 'my': 'Viber ဖြင့် ဆက်သွယ်ပါ'},
      ownerContact: owner,
      upgradeRequest: upgradeRequest,
    );

Widget _app(Widget home, Locale locale, {List<SingleChildWidget> providers = const []}) {
  final app = MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('my')],
    home: home,
  );
  return providers.isEmpty ? app : MultiProvider(providers: providers, child: app);
}

/// Records what the app puts on the clipboard.
List<String> _recordClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
  });

  group('Viber numbers', () {
    test('normalizeViberNumber follows the server rule', () {
      const good = {
        '+959123456789': '+959123456789',
        '09 123 456 789': '+959123456789',
        '09-123-456-789': '+959123456789',
        '(09) 123.456.789': '+959123456789',
        '  09123456789  ': '+959123456789',
        '+66 81 234 5678': '+66812345678',
        '+12345678': '+12345678', // 8 digits
        '+123456789012345': '+123456789012345', // 15 digits
      };
      good.forEach((input, want) => expect(normalizeViberNumber(input), want, reason: input));
      // Nothing typed is "no number", not an error.
      expect(normalizeViberNumber(''), '');
      expect(normalizeViberNumber('  - '), '');
      for (final bad in const [
        'abc', '12345', '+', '+1234567', '+1234567890123456', '0912', '959123456789', '01 234 5678',
        '++959123456789', '+959123456789+', '+95+9123456789', '09 123 456 789 ext 2', '၀၉၁၂၃၄၅၆၇၈၉',
      ]) {
        expect(normalizeViberNumber(bad), isNull, reason: bad);
      }
    });

    test('viberChatUri encodes the plus sign, mailtoUri is a plain mailto', () {
      expect(viberChatUri('+959123456789').toString(), 'viber://chat?number=%2B959123456789');
      expect(viberChatUri('+959123456789').scheme, 'viber');
      expect(mailtoUri('owner@example.com').toString(), 'mailto:owner@example.com');
    });

    test('the owner contact and the request number are read from GET /api/plan', () {
      final status = PlanStatus.fromJson({
        'plan': 'free',
        'owner_contact': {'email': ' owner@example.com ', 'viber': '+959123456789'},
        'upgrade_request': {
          'plan': 'plus',
          'note': null,
          'viber_number': '+959123456789',
          'created_at': '2026-11-03T09:00:00+00:00',
        },
      });
      expect(status.ownerContact.email, 'owner@example.com');
      expect(status.ownerContact.viber, '+959123456789');
      expect(status.upgradeRequest!.viberNumber, '+959123456789');
      // A new request keeps the owner's details.
      expect(status.withUpgradeRequest(null).ownerContact.email, 'owner@example.com');

      final bare = PlanStatus.fromJson({
        'plan': 'free',
        'owner_contact': {'email': '', 'viber': ''},
        'upgrade_request': {'plan': 'pro', 'viber_number': '', 'created_at': '2026-11-03T09:00:00+00:00'},
      });
      expect(bare.ownerContact.isEmpty, isTrue);
      expect(bare.upgradeRequest!.viberNumber, isNull);
      // An older server sends neither.
      final old = PlanStatus.fromJson({'plan': 'free'});
      expect(old.ownerContact.isEmpty, isTrue);
      expect(const OwnerContact(viber: '+959123456789').hasEmail, isFalse);
      expect(const OwnerContact(viber: '+959123456789').isEmpty, isFalse);
    });

    test('the provider hands the number to the requester', () async {
      final sent = <(Plan, String?, String?)>[];
      final provider = PlanProvider(
        loader: () async => _status(),
        requester: (plan, note, viber) async {
          sent.add((plan, note, viber));
          return UpgradeRequest(
            plan: plan,
            note: note,
            viberNumber: viber,
            createdAt: DateTime.utc(2026, 11, 3, 9),
          );
        },
      );
      await provider.refresh();

      await provider.requestUpgrade(Plan.plus, note: 'hi', viberNumber: '+959123456789');
      expect(sent.single, (Plan.plus, 'hi', '+959123456789'));
      expect(provider.upgradeRequest!.viberNumber, '+959123456789');
      expect(provider.status!.ownerContact.email, 'owner@example.com');

      await provider.requestUpgrade(Plan.plus);
      expect(provider.upgradeRequest!.viberNumber, isNull);
      provider.dispose();
    });
  });

  group('Request dialog', () {
    /// Opens the dialog from a button and keeps what it closes with.
    Future<List<UpgradeRequestInput?>> openDialog(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      String? accountEmail = 'me@example.com',
      String? initialViber,
      OwnerContact owner = OwnerContact.none,
    }) async {
      final results = <UpgradeRequestInput?>[];
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open'),
              onPressed: () async => results.add(await showDialog<UpgradeRequestInput>(
                context: context,
                builder: (_) => UpgradeRequestDialog(
                  plan: Plan.plus,
                  accountEmail: accountEmail,
                  initialViber: initialViber,
                  ownerContact: owner,
                ),
              )),
              child: const Text('open'),
            ),
          ),
        ),
        locale,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      return results;
    }

    bool sendEnabled(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(const Key('upgrade-request-send'))).onPressed != null;

    testWidgets('asks for an optional Viber number on a phone keyboard, and says who will email what', (tester) async {
      await openDialog(tester);

      final field = tester.widget<TextField>(find.byKey(const Key('upgrade-request-viber')));
      expect(field.keyboardType, TextInputType.phone);
      expect(field.controller!.text, isEmpty);
      expect(find.text('Viber number (optional)'), findsOneWidget);
      expect(find.text('09 123 456 789'), findsOneWidget); // the hint
      expect(
        find.text('We\'ll contact you on Viber. If you leave it empty, we\'ll email you at me@example.com.'),
        findsOneWidget,
      );
      expect(sendEnabled(tester), isTrue); // no number is fine
    });

    testWidgets('the line names the account email (Myanmar too), or says "your account email" without one', (tester) async {
      await openDialog(tester, locale: const Locale('my'), accountEmail: 'mg@example.com');
      final line = tester.widget<Text>(find.byKey(const Key('upgrade-request-contact-line'))).data!;
      expect(line, contains('mg@example.com'));
      expect(line, contains('Viber'));
      expect(line, contains('မဖြည့်ပါက'));
      expect(find.text('Viber နံပါတ် (မဖြည့်လည်းရသည်)'), findsOneWidget);
      expect(find.text('Send'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await openDialog(tester, accountEmail: null);
      expect(
        find.text('We\'ll contact you on Viber. If you leave it empty, we\'ll email you at your account email.'),
        findsOneWidget,
      );
    });

    testWidgets('is prefilled with the number of the pending request', (tester) async {
      final results = await openDialog(tester, initialViber: '+959123456789');
      expect(tester.widget<TextField>(find.byKey(const Key('upgrade-request-viber'))).controller!.text, '+959123456789');

      await tester.tap(find.byKey(const Key('upgrade-request-send')));
      await tester.pumpAndSettle();
      expect(results.single!.viberNumber, '+959123456789');
      expect(results.single!.note, '');
    });

    testWidgets('sends the number normalised (09… becomes +959…) with the trimmed note', (tester) async {
      final results = await openDialog(tester);
      await tester.enterText(find.byKey(const Key('upgrade-request-viber')), '09 123 456 789');
      await tester.enterText(find.byKey(const Key('upgrade-request-note')), '  hello ');
      await tester.pump();
      await tester.tap(find.byKey(const Key('upgrade-request-send')));
      await tester.pumpAndSettle();

      expect(results.single!.viberNumber, '+959123456789');
      expect(results.single!.note, 'hello');
    });

    testWidgets('an emptied number sends none', (tester) async {
      final results = await openDialog(tester, initialViber: '+959123456789');
      await tester.enterText(find.byKey(const Key('upgrade-request-viber')), '');
      await tester.pump();
      await tester.tap(find.byKey(const Key('upgrade-request-send')));
      await tester.pumpAndSettle();
      expect(results.single!.viberNumber, '');
    });

    for (final (locale, message) in const [
      (Locale('en'), 'Enter a Viber number with its country code, like +959123456789 (or 09 123 456 789).'),
      (Locale('my'), 'နိုင်ငံကုဒ်ပါသော Viber နံပါတ်ကို ထည့်ပါ (ဥပမာ +959123456789 သို့မဟုတ် 09 123 456 789)။'),
    ]) {
      testWidgets('a bad number shows the problem and blocks Send (${locale.languageCode})', (tester) async {
        final results = await openDialog(tester, locale: locale);
        await tester.enterText(find.byKey(const Key('upgrade-request-viber')), '12345');
        await tester.pump();

        expect(find.text(message), findsOneWidget);
        expect(sendEnabled(tester), isFalse);
        await tester.tap(find.byKey(const Key('upgrade-request-send')), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(results, isEmpty); // still open, nothing sent

        await tester.enterText(find.byKey(const Key('upgrade-request-viber')), '+66 81 234 5678');
        await tester.pump();
        expect(find.text(message), findsNothing);
        expect(sendEnabled(tester), isTrue);
      });
    }

    testWidgets('shows "Contact us directly" only when the owner set something', (tester) async {
      await openDialog(tester);
      expect(find.byKey(const Key('owner-contact')), findsNothing);
      expect(find.text('Contact us directly'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await openDialog(tester, owner: const OwnerContact(email: 'owner@example.com'));
      expect(find.text('Contact us directly'), findsOneWidget);
      expect(find.text('owner@example.com'), findsOneWidget);
      expect(find.byKey(const Key('owner-contact-viber')), findsNothing);
    });
  });

  group('Contact us directly', () {
    late List<Uri> launched;
    late bool launchWorks;

    setUp(() {
      launched = [];
      launchWorks = true;
      contactLinkLauncher = (uri) async {
        launched.add(uri);
        return launchWorks;
      };
    });
    tearDown(() {
      contactLinkLauncher = (uri) => throw StateError('restore the real launcher in tests that need it');
    });

    Future<void> pumpBlock(WidgetTester tester, OwnerContact contact, {Locale locale = const Locale('en')}) async {
      await tester.pumpWidget(_app(Scaffold(body: OwnerContactBlock(contact: contact)), locale));
      await tester.pumpAndSettle();
    }

    testWidgets('hides each line that is empty, and the block when both are', (tester) async {
      await pumpBlock(tester, const OwnerContact(email: 'owner@example.com', viber: '+959123456789'));
      expect(find.text('Contact us directly'), findsOneWidget);
      expect(find.text('owner@example.com'), findsOneWidget);
      expect(find.text('+959123456789'), findsOneWidget);

      await pumpBlock(tester, const OwnerContact(email: 'owner@example.com'));
      expect(find.byKey(const Key('owner-contact-email')), findsOneWidget);
      expect(find.byKey(const Key('owner-contact-viber')), findsNothing);

      await pumpBlock(tester, const OwnerContact(viber: '+959123456789'));
      expect(find.byKey(const Key('owner-contact-email')), findsNothing);
      expect(find.byKey(const Key('owner-contact-viber')), findsOneWidget);

      await pumpBlock(tester, OwnerContact.none);
      expect(find.byKey(const Key('owner-contact')), findsNothing);
      expect(find.text('Contact us directly'), findsNothing);
    });

    testWidgets('tapping opens mailto: and the Viber chat', (tester) async {
      await pumpBlock(tester, const OwnerContact(email: 'owner@example.com', viber: '+959123456789'));

      await tester.tap(find.byKey(const Key('owner-contact-email')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('owner-contact-viber')));
      await tester.pump();

      expect(launched.map((u) => u.toString()), ['mailto:owner@example.com', 'viber://chat?number=%2B959123456789']);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('when Viber cannot be opened the number is copied and the user is told', (tester) async {
      final copied = _recordClipboard(tester);
      launchWorks = false;
      await pumpBlock(tester, const OwnerContact(email: 'owner@example.com', viber: '+959123456789'));

      await tester.tap(find.byKey(const Key('owner-contact-viber')));
      await tester.pumpAndSettle();

      expect(copied, ['+959123456789']);
      expect(find.text('Couldn\'t open Viber. The number was copied: +959123456789'), findsOneWidget);
    });

    testWidgets('a launcher that throws counts as "cannot be opened" (email is copied)', (tester) async {
      final copied = _recordClipboard(tester);
      contactLinkLauncher = (uri) async => throw Exception('no handler');
      await pumpBlock(tester, const OwnerContact(email: 'owner@example.com'));

      await tester.tap(find.byKey(const Key('owner-contact-email')));
      await tester.pumpAndSettle();

      expect(copied, ['owner@example.com']);
      expect(find.text('Couldn\'t open your email app. The address was copied: owner@example.com'), findsOneWidget);
    });

    testWidgets('is in Myanmar', (tester) async {
      await pumpBlock(tester, const OwnerContact(email: 'owner@example.com', viber: '+959123456789'), locale: const Locale('my'));
      expect(find.text('Contact us directly'), findsNothing);
      expect(find.text('ကျွန်ုပ်တို့ကို တိုက်ရိုက်ဆက်သွယ်ပါ'), findsOneWidget);
      expect(find.textContaining('အီးမေးလ်'), findsOneWidget);
    });
  });

  group('Upgrade screen', () {
    Future<void> openScreen(
      WidgetTester tester,
      PlanStatus status, {
      Locale locale = const Locale('en'),
      String? signedInAs = 'me@example.com',
      Future<UpgradeRequest> Function(Plan plan, String? note, String? viber)? requester,
    }) async {
      await tester.pumpWidget(_app(
        SubscriptionScreen(),
        locale,
        providers: [
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => signedInAs == null ? AuthProvider() : _SignedInAuth(signedInAs),
          ),
          ChangeNotifierProvider(create: (_) => PlanProvider(loader: () async => status, requester: requester)),
        ],
      ));
      await tester.pumpAndSettle();
    }

    setUp(() {
      contactLinkLauncher = (uri) async => true;
    });

    testWidgets('shows the owner\'s email and Viber number next to the contact message', (tester) async {
      await openScreen(tester, _status());
      await tester.ensureVisible(find.byKey(const Key('upgrade-contact-message')));

      expect(find.text('Message us on Viber'), findsOneWidget);
      expect(find.text('Contact us directly'), findsOneWidget);
      expect(find.text('owner@example.com'), findsOneWidget);
      expect(find.text('+959123456789'), findsOneWidget);
    });

    testWidgets('hides the block when the owner set neither', (tester) async {
      await openScreen(tester, _status(owner: OwnerContact.none));
      expect(find.byKey(const Key('upgrade-contact-message')), findsOneWidget);
      expect(find.byKey(const Key('owner-contact')), findsNothing);
      expect(find.text('Contact us directly'), findsNothing);
    });

    testWidgets('a request with a Viber number: thanks, then the card says Viber', (tester) async {
      final sent = <(Plan, String?, String?)>[];
      await openScreen(
        tester,
        _status(),
        requester: (plan, note, viber) async {
          sent.add((plan, note, viber));
          return UpgradeRequest(plan: plan, note: note, viberNumber: viber, createdAt: DateTime(2026, 11, 3, 12));
        },
      );

      await tester.ensureVisible(find.byKey(const Key('request-plus')));
      await tester.tap(find.byKey(const Key('request-plus')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('upgrade-request-viber')), '09 123 456 789');
      await tester.pump();
      await tester.tap(find.byKey(const Key('upgrade-request-send')));
      await tester.pumpAndSettle();

      expect(sent.single, (Plan.plus, '', '+959123456789'));
      expect(find.text('Thanks! We\'ll contact you soon.'), findsOneWidget);
      expect(
        find.text('Requested on 3 November 2026. We\'ll contact you on Viber at +959123456789.'),
        findsOneWidget,
      );
    });

    testWidgets('a request without a number: the card says we will email the account address', (tester) async {
      await openScreen(
        tester,
        _status(),
        requester: (plan, note, viber) async =>
            UpgradeRequest(plan: plan, note: note, viberNumber: viber, createdAt: DateTime(2026, 11, 3, 12)),
      );

      await tester.ensureVisible(find.byKey(const Key('request-plus')));
      await tester.tap(find.byKey(const Key('request-plus')));
      await tester.pumpAndSettle();
      expect(
        find.text('We\'ll contact you on Viber. If you leave it empty, we\'ll email you at me@example.com.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('upgrade-request-send')));
      await tester.pumpAndSettle();

      expect(find.text('Thanks! We\'ll contact you soon.'), findsOneWidget);
      expect(
        find.text('Requested on 3 November 2026. We\'ll contact you by email at me@example.com.'),
        findsOneWidget,
      );
    });

    testWidgets('an existing request\'s number prefills the dialog when asking again', (tester) async {
      final sent = <(Plan, String?, String?)>[];
      await openScreen(
        tester,
        _status(
          upgradeRequest: UpgradeRequest(plan: Plan.plus, viberNumber: '+959123456789', createdAt: DateTime(2026, 11, 3, 12)),
        ),
        requester: (plan, note, viber) async {
          sent.add((plan, note, viber));
          return UpgradeRequest(plan: plan, note: note, viberNumber: viber, createdAt: DateTime(2026, 11, 4, 12));
        },
      );
      expect(find.text('Requested on 3 November 2026. We\'ll contact you on Viber at +959123456789.'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('request-pro')));
      await tester.tap(find.byKey(const Key('request-pro')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('upgrade-request-viber'))).controller!.text, '+959123456789');
      await tester.tap(find.byKey(const Key('upgrade-request-send')));
      await tester.pumpAndSettle();

      expect(sent.single, (Plan.pro, '', '+959123456789'));
    });

    testWidgets('the request card in Myanmar, both ways', (tester) async {
      await openScreen(
        tester,
        _status(upgradeRequest: UpgradeRequest(plan: Plan.plus, viberNumber: '+959123456789', createdAt: DateTime(2026, 11, 3, 12))),
        locale: const Locale('my'),
      );
      final viberText = tester.widget<Text>(find.byKey(const Key('upgrade-requested-plus'))).data!;
      expect(viberText, contains('+959123456789'));
      expect(viberText, contains('3 နိုဝင်ဘာ 2026'));
      expect(viberText, contains('Viber'));

      await tester.pumpWidget(const SizedBox());
      await openScreen(
        tester,
        _status(upgradeRequest: UpgradeRequest(plan: Plan.plus, createdAt: DateTime(2026, 11, 3, 12))),
        locale: const Locale('my'),
      );
      final emailText = tester.widget<Text>(find.byKey(const Key('upgrade-requested-plus'))).data!;
      expect(emailText, contains('me@example.com'));
      expect(emailText, isNot(contains('Viber')));
    });

    for (final (locale, expected) in const [
      (Locale('en'), 'Enter a Viber number with its country code, like +959123456789 (or 09 123 456 789).'),
      (Locale('my'), 'နိုင်ငံကုဒ်ပါသော Viber နံပါတ်ကို ထည့်ပါ (ဥပမာ +959123456789 သို့မဟုတ် 09 123 456 789)။'),
    ]) {
      testWidgets('a 422 about the Viber number is shown in the app\'s language (${locale.languageCode})', (tester) async {
        await openScreen(
          tester,
          _status(),
          locale: locale,
          requester: (plan, note, viber) async =>
              throw ApiException('Enter a Viber number with its country code, like +959123456789', statusCode: 422),
        );
        await tester.ensureVisible(find.byKey(const Key('request-plus')));
        await tester.tap(find.byKey(const Key('request-plus')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('upgrade-request-send')));
        await tester.pumpAndSettle();

        expect(find.text(expected), findsOneWidget);
        // Not the server's English text.
        expect(find.text('Enter a Viber number with its country code, like +959123456789'), findsNothing);
        expect(find.textContaining('Thanks'), findsNothing);
      });
    }
  });
}
