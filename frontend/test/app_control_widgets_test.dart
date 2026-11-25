import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/app_config.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/app_control_provider.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/budget_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/insight_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/transactions/voice_input_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/announcement_banner.dart';
import 'package:frontend/widgets/paused_feature.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _announcementJson({String updatedAt = 't1', String? link}) => {
      'id': 'a1',
      'updated_at': updatedAt,
      'style': 'info',
      'text': 'Sale this weekend',
      'link_url': link,
      'link_label': link == null ? '' : 'Read more',
    };

AppConfig _config({Map<String, String> paused = const {}, Map<String, dynamic>? announcement}) =>
    AppConfig.fromJson({
      'maintenance': {'on': false, 'message': '', 'back_by': null, 'can_enter': true},
      'paused': paused,
      'announcement': announcement,
    });

/// A provider whose config can be swapped without a server.
AppControlProvider _provider(AppConfig config) => AppControlProvider(fetcher: () async => config);

Widget _app(Widget home, AppControlProvider? control, {List<SingleChildWidget> extra = const []}) {
  final app = MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('my')],
    home: home,
  );
  final providers = <SingleChildWidget>[
    if (control != null) ChangeNotifierProvider<AppControlProvider>.value(value: control),
    ...extra,
  ];
  return providers.isEmpty ? app : MultiProvider(providers: providers, child: app);
}

class _NoTransactions extends TransactionProvider {
  @override
  List<Transaction> get transactions => const [];
  @override
  List<Transaction> get weekOutflows => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchTransactions({int? limit, int? skip, TransactionType? type, DateTime? startDate, DateTime? endDate, Currency? currency}) async {}
  @override
  Future<void> fetchWeekSpending({DateTime? today}) async {}
  @override
  Future<void> fetchBalance({Currency? currency}) async {}
}

class _NoBudgets extends BudgetProvider {
  @override
  List<Budget> get budgets => const [];
  @override
  List<Budget> get activeBudgets => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchBudgets({bool activeOnly = false, BudgetPeriod? period, Currency? currency}) async {}
  @override
  Future<void> fetchMultiCurrencySummary() async {}
}

class _NoGoals extends GoalProvider {
  @override
  List<Goal> get goals => const [];
  @override
  List<Goal> get activeGoals => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchGoals({GoalStatus? statusFilter, Currency? currency}) async {}
  @override
  Future<void> fetchSummary({Currency? currency}) async {}
  @override
  Future<void> fetchMultiCurrencySummary() async {}
}

class _NoChat extends ChatProvider {
  @override
  Future<void> loadChatHistory() async {}
}

class _FakeNotifications extends NotificationProvider {
  @override
  Future<void> fetchUnreadCount() async {}
}

Future<void> _pumpBanner(WidgetTester tester, AppControlProvider control) async {
  await tester.pumpWidget(_app(const Scaffold(body: AnnouncementBanner()), control));
  await tester.pumpAndSettle();
}

Future<void> _pumpHome(WidgetTester tester, AppControlProvider control) async {
  tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(
    const HomeScreen(),
    control,
    extra: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<TransactionProvider>(create: (_) => _NoTransactions()),
      ChangeNotifierProvider<BudgetProvider>(create: (_) => _NoBudgets()),
      ChangeNotifierProvider<GoalProvider>(create: (_) => _NoGoals()),
      ChangeNotifierProvider<ChatProvider>(create: (_) => _NoChat()),
      ChangeNotifierProvider<InsightProvider>(create: (_) => InsightProvider()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => _FakeNotifications()),
      ChangeNotifierProvider<PlanProvider>(create: (_) => PlanProvider()),
    ],
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AnnouncementBanner', () {
    testWidgets('shows the text', (tester) async {
      await _pumpBanner(tester, _provider(_config(announcement: _announcementJson())));
      expect(find.text('Sale this weekend'), findsOneWidget);
    });

    testWidgets('shows a link label when there is a link', (tester) async {
      await _pumpBanner(
          tester, _provider(_config(announcement: _announcementJson(link: 'https://example.com'))));
      expect(find.text('Read more'), findsOneWidget);
    });

    testWidgets('an https link opens through the launcher', (tester) async {
      final opened = <Uri>[];
      final saved = announcementLinkLauncher;
      announcementLinkLauncher = (uri) async {
        opened.add(uri);
        return true;
      };
      addTearDown(() => announcementLinkLauncher = saved);
      await _pumpBanner(
          tester, _provider(_config(announcement: _announcementJson(link: 'https://example.com/a'))));
      await tester.tap(find.text('Read more'));
      await tester.pump();
      expect(opened, [Uri.parse('https://example.com/a')]);
    });

    for (final bad in ['javascript:alert(1)', 'tel:+959000000', 'intent://x#Intent;end', 'not a url', '//example.com']) {
      testWidgets('a "$bad" link is not shown and never launches', (tester) async {
        final opened = <Uri>[];
        final saved = announcementLinkLauncher;
        announcementLinkLauncher = (uri) async {
          opened.add(uri);
          return true;
        };
        addTearDown(() => announcementLinkLauncher = saved);
        await _pumpBanner(tester, _provider(_config(announcement: _announcementJson(link: bad))));
        expect(find.text('Sale this weekend'), findsOneWidget);
        expect(find.text('Read more'), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(opened, isEmpty);
      });
    }

    testWidgets('shows nothing when there is no announcement', (tester) async {
      await _pumpBanner(tester, _provider(_config()));
      expect(find.byType(Text), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('closing hides it, stores id@updatedAt and it stays hidden on rebuild', (tester) async {
      final control = _provider(_config(announcement: _announcementJson()));
      await _pumpBanner(tester, control);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Sale this weekend'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('dismissed_announcement'), 'a1@t1');

      // A fresh build of the banner (a new visit to the dashboard).
      await tester.pumpWidget(const SizedBox());
      await _pumpBanner(tester, control);
      expect(find.text('Sale this weekend'), findsNothing);
    });

    testWidgets('an edited announcement (new updatedAt) shows again', (tester) async {
      SharedPreferences.setMockInitialValues({'dismissed_announcement': 'a1@t1'});
      await _pumpBanner(tester, _provider(_config(announcement: _announcementJson())));
      expect(find.text('Sale this weekend'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await _pumpBanner(tester, _provider(_config(announcement: _announcementJson(updatedAt: 't2'))));
      expect(find.text('Sale this weekend'), findsOneWidget);
    });
  });

  group('showIfPaused and PausedLook', () {
    Future<BuildContext> pumpProbe(WidgetTester tester, AppControlProvider? control) async {
      late BuildContext captured;
      await tester.pumpWidget(_app(
        Scaffold(
          body: Builder(builder: (context) {
            captured = context;
            return PausedLook(featureKey: 'chat', child: const Text('Chat button'));
          }),
        ),
        control,
      ));
      await tester.pumpAndSettle();
      return captured;
    }

    double opacityOfButton(WidgetTester tester) => tester
        .widget<Opacity>(find.ancestor(of: find.text('Chat button'), matching: find.byType(Opacity)).first)
        .opacity;

    testWidgets('paused: shows the message, returns true, greys the child', (tester) async {
      final control = _provider(_config(paused: {'chat': 'Chat is paused for now.'}));
      final context = await pumpProbe(tester, control);
      expect(opacityOfButton(tester), 0.4);

      expect(showIfPaused(context, 'chat'), isTrue);
      await tester.pump();
      expect(find.text('Chat is paused for now.'), findsOneWidget);
    });

    testWidgets('not paused: false, no message, child at full strength', (tester) async {
      final control = _provider(_config(paused: {'voice': 'Voice is paused.'}));
      final context = await pumpProbe(tester, control);
      expect(opacityOfButton(tester), 1.0);

      expect(showIfPaused(context, 'chat'), isFalse);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('no provider: nothing is paused', (tester) async {
      final context = await pumpProbe(tester, null);
      expect(opacityOfButton(tester), 1.0);
      expect(showIfPaused(context, 'chat'), isFalse);
    });
  });

  group('entry points', () {
    testWidgets('voice button on the home screen shows the message instead of opening voice entry',
        (tester) async {
      final control = _provider(_config(paused: {'voice': 'Voice entry is paused for now.'}));
      await _pumpHome(tester, control);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppLocalizations(const Locale('en')).voiceInput));
      await tester.pumpAndSettle();

      expect(find.byType(VoiceInputScreen), findsNothing);
      expect(find.text('Voice entry is paused for now.'), findsOneWidget);
    });

    testWidgets('the home screen shows the banner at the top', (tester) async {
      final control = _provider(_config(announcement: _announcementJson()));
      await _pumpHome(tester, control);
      expect(find.text('Sale this weekend'), findsOneWidget);
    });
  });
}
