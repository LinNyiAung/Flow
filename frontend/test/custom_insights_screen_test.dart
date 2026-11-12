import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/custom_insight.dart';
import 'package:frontend/models/insight.dart';
import 'package:frontend/models/notification.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/custom_insight_provider.dart';
import 'package:frontend/providers/insight_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/insights/custom_insight_form.dart';
import 'package:frontend/screens/insights/custom_insight_report_screen.dart';
import 'package:frontend/screens/insights/custom_insights_tab.dart';
import 'package:frontend/screens/insights/insights_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/custom_insight_push.dart';
import 'package:frontend/widgets/app_bar_title.dart';
import 'package:frontend/widgets/mascot.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _refusal = "That isn't something I can answer from your finances";

/// An [AuthProvider] with a chosen plan.
class _Auth extends AuthProvider {
  _Auth({this.pro = false, this.paid = false});
  final bool pro;
  final bool paid;

  @override
  bool get isPro => pro;
  @override
  bool get isPaid => paid;
}

PlanStatus _plan({String custom = 'counted', String translation = 'locked', String weekly = 'locked'}) {
  FeatureAllowance allowance(String mode) => switch (mode) {
        'locked' => const FeatureAllowance(mode: 'locked'),
        'counted' => const FeatureAllowance(
            mode: 'counted', limit: 10, used: 2, remaining: 8, period: 'month'),
        _ => const FeatureAllowance(mode: 'included'),
      };
  return PlanStatus(
    plan: custom == 'locked' ? Plan.free : Plan.pro,
    features: {
      PlanFeature.insightCustom: allowance(custom),
      PlanFeature.insightTranslation: allowance(translation),
      PlanFeature.insightWeekly: allowance(weekly),
      PlanFeature.insightMonthly: const FeatureAllowance(mode: 'included'),
    },
  );
}

Map<String, dynamic> _json({
  String id = 'r1',
  String status = 'ready',
  String? content = '## Summary\nAll good.',
  String? contentMm,
  String? instruction,
  String? preset,
  bool figures = true,
  String createdAt = '2026-11-02T08:15:00+00:00',
}) =>
    {
      'id': id,
      'start_date': '2026-10-01',
      'end_date': '2026-10-31',
      'preset': preset,
      'instruction': instruction,
      'status': status,
      'created_at': createdAt,
      'completed_at': status == 'pending' ? null : '2026-11-02T08:15:20+00:00',
      'has_myanmar': contentMm != null,
      'content': content,
      'content_mm': contentMm,
      'figures': figures
          ? {
              'previous_start': '2026-08-31',
              'previous_end': '2026-09-30',
              'currencies': [
                {
                  'currency': 'USD',
                  'income': 500.0,
                  'spending': 250.0,
                  'net': 250.0,
                  'transactions': 12,
                  'top_categories': [
                    for (var i = 1; i <= 6; i++)
                      {'main_category': 'Cat$i', 'sub_category': 'Sub$i', 'amount': 100.0 - i},
                  ],
                  'previous_income': 0.0,
                  'previous_spending': 100.0,
                  'income_change_pct': null,
                  'spending_change_pct': 150.0,
                }
              ],
            }
          : null,
    };

CustomInsight _report(Map<String, dynamic> json) => CustomInsight.fromJson(json);

class FakeCustomInsightClient implements CustomInsightClient {
  List<CustomInsight> reports = [];
  CustomInsight? detail;
  Object? getError;
  CustomInsightCreateResult? createResult;
  CustomInsightRequest? lastRequest;
  int createCalls = 0;
  int getCalls = 0;
  CustomInsight? translateResult;
  Object? translateError;
  int translateCalls = 0;
  final List<String> deleted = [];

  /// Reports per page (0: all on one page). The fake's cursor is the last id.
  int pageSize = 0;
  final List<String?> listBefores = [];

  @override
  Future<CustomInsightPage> list({String? before}) async {
    listBefores.add(before);
    final visible = [
      for (final r in reports)
        if (!deleted.contains(r.id)) r
    ];
    final start = before == null ? 0 : visible.indexWhere((r) => r.id == before) + 1;
    final end = pageSize == 0 ? visible.length : (start + pageSize).clamp(0, visible.length);
    final page = visible.sublist(start, end);
    return CustomInsightPage(reports: page, nextBefore: end < visible.length ? page.last.id : null);
  }

  @override
  Future<CustomInsight> get(String id) async {
    getCalls++;
    if (getError != null) throw getError!;
    return detail!;
  }

  @override
  Future<CustomInsightCreateResult> create(CustomInsightRequest request) async {
    createCalls++;
    lastRequest = request;
    return createResult!;
  }

  @override
  Future<CustomInsight> translate(String id) async {
    translateCalls++;
    if (translateError != null) throw translateError!;
    return translateResult!;
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
  }
}

Future<void> _bigScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The provider of the last [_pump].
late CustomInsightProvider _provider;

/// Pumps [home] with the providers the custom insight screens read.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required FakeCustomInsightClient fake,
  PlanStatus? plan,
  bool pro = true,
  bool paid = true,
  InsightProvider? insights,
  Locale locale = const Locale('en'),
  RouteFactory? onGenerateRoute,
  bool settle = true,
}) async {
  await _bigScreen(tester);
  final planProvider = PlanProvider(loader: () async => plan ?? _plan());
  await planProvider.refresh();
  final custom = CustomInsightProvider(
    client: fake,
    pollInterval: const Duration(hours: 1),
    onUsageChanged: () {},
  );
  _provider = custom;
  addTearDown(() {
    custom.dispose();
    planProvider.dispose();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(pro: pro, paid: paid)),
        ChangeNotifierProvider<PlanProvider>.value(value: planProvider),
        ChangeNotifierProvider<CustomInsightProvider>.value(value: custom),
        ChangeNotifierProvider<InsightProvider>.value(value: insights ?? InsightProvider(fetcher: _noInsight)),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('my')],
        routes: {'/subscription': (_) => const Scaffold(body: Text('subscription screen'))},
        onGenerateRoute: onGenerateRoute,
        home: onGenerateRoute == null ? home : null,
      ),
    ),
  );
  await _settle(tester, settle);
}

/// Lets animations and futures finish. A spinner (a report being created) never
/// stops animating, so those tests pass settle: false for a few timed pumps.
Future<void> _settle(WidgetTester tester, [bool settle = true]) async {
  if (settle) {
    await tester.pumpAndSettle();
    return;
  }
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<Insight> _noInsight({required String language, required String insightType}) async =>
    throw Exception('no insight in this test');

/// A page with a button that opens the create form.
class _FormHost extends StatelessWidget {
  const _FormHost({this.today});
  final DateTime? today;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('open-form'),
            onPressed: () => showCustomInsightForm(context, today: today),
            child: const Text('open'),
          ),
        ),
      );
}

Finder _itemKeys() => find.byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> && key.value.startsWith('custom-insight-item-');
    });

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'access_token': 'tok'}));

  group('Custom tab', () {
    testWidgets('locked_plus_no_reports: only the locked card with Upgrade', (tester) async {
      final fake = FakeCustomInsightClient();
      await _pump(tester, const Scaffold(body: CustomInsightsTab()),
          fake: fake, plan: _plan(custom: 'locked'), pro: false, paid: false);

      expect(find.byKey(const Key('custom-insight-locked')), findsOneWidget);
      expect(find.text('Custom insights come with Pro'), findsOneWidget);
      expect(find.byKey(const Key('custom-insight-new')), findsNothing);
      expect(_itemKeys(), findsNothing);
      expect(find.text('No custom insights yet.'), findsNothing);

      await tester.tap(find.byKey(const Key('custom-insight-upgrade')));
      await tester.pumpAndSettle();
      expect(find.text('subscription screen'), findsOneWidget);
    });

    testWidgets('locked while the plan is unknown follows the account (not Pro)', (tester) async {
      final fake = FakeCustomInsightClient();
      await _bigScreen(tester);
      // A plan that never loads.
      final plan = PlanProvider(loader: () async => throw Exception('offline'));
      final custom = CustomInsightProvider(client: fake, onUsageChanged: () {});
      addTearDown(custom.dispose);
      addTearDown(plan.dispose);
      Widget app(bool pro) => MultiProvider(
            key: ValueKey(pro),
            providers: [
              ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(pro: pro)),
              ChangeNotifierProvider<PlanProvider>.value(value: plan),
              ChangeNotifierProvider<CustomInsightProvider>.value(value: custom),
            ],
            child: const MaterialApp(
              localizationsDelegates: [AppLocalizations.delegate],
              supportedLocales: [Locale('en'), Locale('my')],
              home: Scaffold(body: CustomInsightsTab()),
            ),
          );

      await tester.pumpWidget(app(false));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('custom-insight-locked')), findsOneWidget);

      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('custom-insight-locked')), findsNothing);
      expect(find.byKey(const Key('custom-insight-new')), findsOneWidget);
    });

    testWidgets('locked_with_past_reports: locked card and the list', (tester) async {
      final fake = FakeCustomInsightClient()
        ..reports = [
          _report(_json(id: 'a', preset: 'where_to_save', content: null, figures: false)),
          _report(_json(id: 'b', instruction: 'Why so much on food?', content: null, figures: false)),
        ];
      await _pump(tester, const Scaffold(body: CustomInsightsTab()),
          fake: fake, plan: _plan(custom: 'locked'), pro: false, paid: false);

      expect(find.byKey(const Key('custom-insight-locked')), findsOneWidget);
      expect(find.byKey(const Key('custom-insight-new')), findsNothing);
      expect(find.byKey(const Key('custom-insight-item-a')), findsOneWidget);
      expect(find.byKey(const Key('custom-insight-item-b')), findsOneWidget);
      expect(find.text('Where can I save?'), findsOneWidget);
      expect(find.text('Why so much on food?'), findsOneWidget);

      // Delete still works.
      await tester.tap(find.byKey(const Key('custom-insight-delete-a')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this custom insight?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('custom-insight-delete-confirm')));
      await tester.pumpAndSettle();
      expect(fake.deleted, ['a']);
      expect(find.byKey(const Key('custom-insight-item-a')), findsNothing);
      expect(find.byKey(const Key('custom-insight-item-b')), findsOneWidget);
    });

    testWidgets('list_status_lines: refused reads the exact refusal sentence; failed says not counted',
        (tester) async {
      final fake = FakeCustomInsightClient()
        ..reports = [
          _report(_json(id: 'p', status: 'pending', content: null, figures: false)),
          _report(_json(id: 'f', status: 'failed', content: null, figures: false)),
          _report(_json(id: 'x', status: 'refused', content: null, figures: false, instruction: 'Write a poem')),
          _report(_json(id: 'ok', figures: false)),
        ];
      await _pump(tester, const Scaffold(body: CustomInsightsTab()), fake: fake, settle: false);

      String status(String id) => tester.widget<Text>(find.byKey(Key('custom-insight-status-$id'))).data!;
      expect(status('x'), _refusal);
      expect(status('f'), "Couldn't be created. It wasn't counted.");
      expect(status('p'), 'Being created…');
      expect(status('ok'), isNot(_refusal));
      // No instruction and no preset reads "Full insight".
      expect(find.text('Full insight'), findsWidgets);
      expect(find.text('Write a poem'), findsOneWidget);
      // A pending report cannot be deleted yet.
      expect(find.byKey(const Key('custom-insight-delete-p')), findsNothing);
      expect(find.byKey(const Key('custom-insight-delete-f')), findsOneWidget);

      _provider.reset(); // stops the polling timer of the pending report
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('load_more_row: 30 shown, "Load more" appends the next page, then the row is gone', (tester) async {
      final fake = FakeCustomInsightClient()
        ..pageSize = 30
        ..reports = [
          for (var i = 0; i < 35; i++)
            _report(_json(
              id: 'r${100 - i}',
              content: null,
              figures: false,
              createdAt: DateTime.utc(2026, 11, 2, 8).subtract(Duration(hours: i)).toIso8601String(),
            )),
        ];
      await _pump(tester, const Scaffold(body: CustomInsightsTab()), fake: fake);

      final loadMore = find.byKey(const Key('custom-insight-load-more'));
      expect(_itemKeys(), findsNWidgets(30));
      expect(loadMore, findsOneWidget);
      expect(find.text('Load more'), findsOneWidget);

      await tester.ensureVisible(loadMore);
      await tester.pumpAndSettle();
      await tester.tap(loadMore);
      await tester.pumpAndSettle();

      expect(fake.listBefores, [null, 'r71']);
      expect(_itemKeys(), findsNWidgets(35));
      expect(find.byKey(const Key('custom-insight-item-r66')), findsOneWidget);
      expect(loadMore, findsNothing);
    });

    testWidgets('a short list has no "Load more" row', (tester) async {
      final fake = FakeCustomInsightClient()
        ..pageSize = 30
        ..reports = [_report(_json(id: 'a', figures: false))];
      await _pump(tester, const Scaffold(body: CustomInsightsTab()), fake: fake);
      expect(_itemKeys(), findsOneWidget);
      expect(find.byKey(const Key('custom-insight-load-more')), findsNothing);
    });

    testWidgets('pending_disables_new: while a report is being created, New is disabled and says why', (tester) async {
      final fake = FakeCustomInsightClient()
        ..reports = [_report(_json(id: 'p', status: 'pending', content: null, figures: false))];
      await _pump(tester, const Scaffold(body: CustomInsightsTab()), fake: fake, settle: false);

      expect(tester.widget<FilledButton>(find.byKey(const Key('custom-insight-new'))).onPressed, isNull);
      expect(find.byKey(const Key('custom-insight-pending-hint')), findsOneWidget);
      expect(find.text('Your previous custom insight is still being created.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('custom-insight-new')), warnIfMissed: false);
      await _settle(tester, false);
      expect(find.byKey(const Key('custom-insight-create')), findsNothing);

      _provider.reset(); // stops the polling timer of the pending report
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('pro_tab_usage_and_form: "8 of 10 left this month", preset chip sends where_to_save',
        (tester) async {
      final fake = FakeCustomInsightClient()
        ..createResult = CustomInsightCreateResult(
          report: _report(_json(id: 'n', status: 'pending', preset: 'where_to_save', content: null, figures: false)),
          reused: false,
        );
      await _pump(tester, const Scaffold(body: CustomInsightsTab()), fake: fake);

      expect(find.text('8 of 10 left this month'), findsOneWidget);
      expect(find.text('No custom insights yet.'), findsOneWidget);
      expect(find.byKey(const Key('custom-insight-locked')), findsNothing);
      expect(find.byKey(const Key('custom-insight-pending-hint')), findsNothing);

      await tester.tap(find.byKey(const Key('custom-insight-new')));
      await tester.pumpAndSettle();

      // Typing clears the chip; picking a chip clears the text.
      await tester.tap(find.byKey(const Key('custom-preset-biggest_changes')));
      await tester.pump();
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('custom-preset-biggest_changes'))).selected, isTrue);
      await tester.enterText(find.byKey(const Key('custom-instruction-field')), 'my own question');
      await tester.pump();
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('custom-preset-biggest_changes'))).selected, isFalse);
      await tester.tap(find.byKey(const Key('custom-preset-where_to_save')));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('custom-instruction-field'))).controller!.text, '');

      await tester.tap(find.byKey(const Key('custom-insight-create')));
      await _settle(tester, false);

      expect(fake.createCalls, 1);
      expect(fake.lastRequest!.preset, 'where_to_save');
      expect(fake.lastRequest!.instruction, isNull);
      expect(find.text("Creating your insight. We'll let you know when it's ready."), findsOneWidget);
      // The new report is in the list, being created; New waits for it.
      expect(find.byKey(const Key('custom-insight-item-n')), findsOneWidget);
      expect(find.byKey(const Key('custom-insight-create')), findsNothing);
      expect(find.byKey(const Key('custom-insight-pending-hint')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('custom-insight-new'))).onPressed, isNull);

      _provider.reset(); // stops the polling timer of the pending report
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a typed question is sent trimmed, without a preset', (tester) async {
      final fake = FakeCustomInsightClient()
        ..createResult = CustomInsightCreateResult(
          report: _report(_json(id: 'n', status: 'pending', instruction: 'Why?', content: null, figures: false)),
          reused: false,
        );
      await _pump(tester, const Scaffold(body: CustomInsightsTab()), fake: fake);
      await tester.tap(find.byKey(const Key('custom-insight-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('custom-instruction-field')), '  Why?  ');
      await tester.tap(find.byKey(const Key('custom-insight-create')));
      await _settle(tester, false);

      expect(fake.lastRequest!.preset, isNull);
      expect(fake.lastRequest!.toJson()['instruction'], 'Why?');
      _provider.reset(); // stops the polling timer of the pending report
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a reused report shows the saved-one message and opens the report', (tester) async {
      final fake = FakeCustomInsightClient()
        ..createResult = CustomInsightCreateResult(report: _report(_json(id: 'old')), reused: true)
        ..detail = _report(_json(id: 'old'));
      await _pump(tester, const Scaffold(body: CustomInsightsTab()), fake: fake);
      await tester.tap(find.byKey(const Key('custom-insight-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-insight-create')));
      await tester.pumpAndSettle();

      expect(find.text('You already have this insight, so here is the saved one.'), findsOneWidget);
      expect(find.byKey(const Key('custom-report-body')), findsOneWidget);
    });

    for (final c in [
      (CustomInsightRequestException.pending, 'Your previous custom insight is still being created.'),
      (CustomInsightRequestException.noData, 'There are no transactions in these dates.'),
    ]) {
      testWidgets('create error ${c.$1} shows its own message in the form', (tester) async {
        final failing = _ThrowingCreate(CustomInsightRequestException(
          code: c.$1,
          statusCode: 409,
          message: 'server words',
        ));
        await _pump(tester, const Scaffold(body: CustomInsightsTab()), fake: failing);
        await tester.tap(find.byKey(const Key('custom-insight-new')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('custom-insight-create')));
        await tester.pumpAndSettle();

        expect(find.text(c.$2), findsOneWidget);
        expect(find.text('server words'), findsNothing);
        expect(find.byKey(const Key('custom-insight-create')), findsOneWidget);
      });
    }

    testWidgets('create with a plan limit opens the limit sheet over the form', (tester) async {
      final failing = _ThrowingCreate(PlanLimitException(
        code: PlanLimitException.codeLimitReached,
        statusCode: 429,
        feature: PlanFeature.insightCustom,
        message: 'used up',
        upgradeAvailable: true,
      ));
      await _pump(tester, const Scaffold(body: CustomInsightsTab()), fake: failing);
      await tester.tap(find.byKey(const Key('custom-insight-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-insight-create')));
      await tester.pumpAndSettle();

      expect(find.text("You've reached your limit"), findsOneWidget);
      // No inline error for a plan limit; the form is still there under the sheet.
      expect(find.byKey(const Key('custom-insight-error')), findsNothing);
      expect(find.byKey(const Key('custom-insight-create')), findsOneWidget);
    });

    testWidgets('a create error shows the string for its code in the form', (tester) async {
      final fake = FakeCustomInsightClient();
      final failing = _ThrowingCreate(CustomInsightRequestException(
        code: CustomInsightRequestException.attempts,
        statusCode: 429,
        message: 'server words',
      ));
      await _pump(tester, const Scaffold(body: CustomInsightsTab()), fake: failing..reports = fake.reports);
      await tester.tap(find.byKey(const Key('custom-insight-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-insight-create')));
      await tester.pumpAndSettle();

      expect(find.text('Too many custom insights could not be created today. Please try again tomorrow.'),
          findsOneWidget);
      expect(find.text('server words'), findsNothing);
      // The form stays open for another try.
      expect(find.byKey(const Key('custom-insight-create')), findsOneWidget);
    });
  });

  test('today is the date in the app timezone (Asia/Yangon, UTC+06:30)', () {
    // 17:29 UTC is 23:59 in Yangon; one minute later it is the next day there.
    expect(customInsightToday(DateTime.utc(2026, 11, 4, 17, 29)), DateTime(2026, 11, 4));
    expect(customInsightToday(DateTime.utc(2026, 11, 4, 17, 30)), DateTime(2026, 11, 5));
    expect(customInsightToday(DateTime.utc(2026, 12, 31, 18)), DateTime(2027, 1, 1));
  });

  group('Create form', () {
    testWidgets('form_disables_create_for_short_range_and_thisYear_in_early_january', (tester) async {
      // Early January: "this year so far" is 3 days, under the 7-day minimum.
      await _pump(tester, _FormHost(today: DateTime(2027, 1, 3)), fake: FakeCustomInsightClient());
      await tester.tap(find.byKey(const Key('open-form')));
      await tester.pumpAndSettle();

      expect(tester.widget<ChoiceChip>(find.byKey(const Key('custom-range-thisYear'))).onSelected, isNull);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('custom-range-last30Days'))).onSelected, isNotNull);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('custom-range-last3Months'))).onSelected, isNotNull);
      expect(tester.widget<FilledButton>(find.byKey(const Key('custom-insight-create'))).onPressed, isNotNull);
    });

    testWidgets('a picked range under 7 days disables Create and says why', (tester) async {
      await _pump(tester, _FormHost(today: DateTime(2026, 11, 18)), fake: FakeCustomInsightClient());
      await tester.tap(find.byKey(const Key('open-form')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('custom-range-problem')), findsNothing);

      await tester.tap(find.byKey(const Key('custom-range-pick')));
      await tester.pumpAndSettle();
      // The picker: choose 10 and 12 November, then save.
      await tester.tap(find.text('10').last);
      await tester.pump();
      await tester.tap(find.text('12').last);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Choose at least 7 days.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('custom-insight-create'))).onPressed, isNull);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('custom-range-pick'))).selected, isTrue);

      // Another quick range fixes it.
      await tester.tap(find.byKey(const Key('custom-range-last3Months')));
      await tester.pump();
      expect(find.text('Choose at least 7 days.'), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const Key('custom-insight-create'))).onPressed, isNotNull);
    });

    testWidgets('the instruction is limited to 300 characters', (tester) async {
      await _pump(tester, const _FormHost(), fake: FakeCustomInsightClient());
      await tester.tap(find.byKey(const Key('open-form')));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.byKey(const Key('custom-instruction-field'))).maxLength, 300);
      await tester.enterText(find.byKey(const Key('custom-instruction-field')), 'a' * 350);
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('custom-instruction-field'))).controller!.text.length, 300);
    });
  });

  group('Report screen', () {
    testWidgets('report_figures_and_markdown: custom-figures-usd shows 250.00 spending; MarkdownBody shown',
        (tester) async {
      final fake = FakeCustomInsightClient()..detail = _report(_json(instruction: 'Why so much on food?'));
      await _pump(tester, const CustomInsightReportScreen(reportId: 'r1'), fake: fake);

      final figures = find.byKey(const Key('custom-figures-usd'));
      expect(figures, findsOneWidget);
      expect(find.descendant(of: figures, matching: find.textContaining('250.00')), findsWidgets);
      expect(find.descendant(of: figures, matching: find.text('Spending')), findsOneWidget);
      expect(find.descendant(of: figures, matching: find.text('Income')), findsOneWidget);
      expect(find.descendant(of: figures, matching: find.text('Net')), findsOneWidget);
      // Spending was 100 before: +150.0%. Income had nothing before.
      expect(find.descendant(of: figures, matching: find.textContaining('+150.0%')), findsOneWidget);
      expect(find.descendant(of: figures, matching: find.text('Nothing to compare with')), findsOneWidget);
      // At most five top categories.
      expect(find.descendant(of: figures, matching: find.textContaining('Cat5')), findsOneWidget);
      expect(find.descendant(of: figures, matching: find.textContaining('Cat6')), findsNothing);

      expect(find.byKey(const Key('custom-report-body')), findsOneWidget);
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('Why so much on food?'), findsOneWidget);
      expect(find.text('1 Oct – 31 Oct 2026'), findsOneWidget);
      // English first, nothing translated on open.
      expect(fake.translateCalls, 0);
    });

    testWidgets('report_table_shown_as_plain_text: no MarkdownBody, no "|" in the text', (tester) async {
      const table = '## Summary\n\n| Category | Amount |\n|---|---|\n| Food | 90 |\n';
      final fake = FakeCustomInsightClient()..detail = _report(_json(content: table));
      await _pump(tester, const CustomInsightReportScreen(reportId: 'r1'), fake: fake);

      expect(find.byType(MarkdownBody), findsNothing);
      final text = tester.widget<SelectableText>(find.descendant(
        of: find.byKey(const Key('custom-report-body')),
        matching: find.byType(SelectableText),
      ));
      expect(text.data, contains('Food'));
      expect(text.data, isNot(contains('|')));
    });

    testWidgets('report_myanmar_stored_shown_without_translate_call', (tester) async {
      final fake = FakeCustomInsightClient()
        ..detail = _report(_json(contentMm: '## အနှစ်ချုပ်\nကောင်းပါသည်။'));
      // A Free account: a stored Myanmar text is shown whatever the plan.
      await _pump(tester, const CustomInsightReportScreen(reportId: 'r1'), fake: fake, pro: false, paid: false);

      expect(find.descendant(of: find.byKey(const Key('custom-lang-mm')), matching: find.byIcon(Icons.lock_rounded)),
          findsNothing);
      await tester.tap(find.byKey(const Key('custom-lang-mm')));
      await tester.pumpAndSettle();

      expect(find.text('ကောင်းပါသည်။'), findsOneWidget);
      expect(fake.translateCalls, 0);

      await tester.tap(find.byKey(const Key('custom-lang-en')));
      await tester.pumpAndSettle();
      expect(find.text('All good.'), findsOneWidget);
    });

    testWidgets('report_myanmar_locked_opens_upgrade', (tester) async {
      final fake = FakeCustomInsightClient()..detail = _report(_json());
      await _pump(tester, const CustomInsightReportScreen(reportId: 'r1'),
          fake: fake, plan: _plan(translation: 'locked'), pro: false, paid: false);

      expect(find.descendant(of: find.byKey(const Key('custom-lang-mm')), matching: find.byIcon(Icons.lock_rounded)),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('custom-lang-mm')));
      await tester.pumpAndSettle();

      expect(find.text('subscription screen'), findsOneWidget);
      expect(fake.translateCalls, 0);
    });

    testWidgets('Myanmar without a stored text is translated once the user asks', (tester) async {
      final fake = FakeCustomInsightClient()
        ..detail = _report(_json())
        ..translateResult = _report(_json(contentMm: 'မြန်မာ စာသား'));
      await _pump(tester, const CustomInsightReportScreen(reportId: 'r1'),
          fake: fake, plan: _plan(translation: 'included'));

      expect(fake.translateCalls, 0);
      expect(find.descendant(of: find.byKey(const Key('custom-lang-mm')), matching: find.byIcon(Icons.lock_rounded)),
          findsNothing);
      await tester.tap(find.byKey(const Key('custom-lang-mm')));
      await tester.pumpAndSettle();

      expect(fake.translateCalls, 1);
      expect(find.text('မြန်မာ စာသား'), findsOneWidget);
    });

    testWidgets('a refused translation shows the plan limit sheet and stays in English', (tester) async {
      final fake = FakeCustomInsightClient()
        ..detail = _report(_json())
        ..translateError = PlanLimitException(
          code: PlanLimitException.codeLimitReached,
          statusCode: 429,
          feature: PlanFeature.insightTranslation,
          message: 'used up',
          upgradeAvailable: true,
        );
      await _pump(tester, const CustomInsightReportScreen(reportId: 'r1'),
          fake: fake, plan: _plan(translation: 'counted'));
      await tester.tap(find.byKey(const Key('custom-lang-mm')));
      await tester.pumpAndSettle();

      expect(find.text("You've reached your limit"), findsOneWidget);
      expect(find.text('All good.'), findsOneWidget);
    });

    testWidgets('report_screen_deleted_state', (tester) async {
      final fake = FakeCustomInsightClient()..getError = ApiException('Custom insight not found', statusCode: 404);
      await _pump(tester, const CustomInsightReportScreen(reportId: 'gone'), fake: fake);

      expect(find.byKey(const Key('custom-report-deleted')), findsOneWidget);
      expect(find.text('This custom insight was deleted.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('custom-report-body')), findsNothing);
    });

    testWidgets('another failure shows a retry, not the deleted state', (tester) async {
      final fake = FakeCustomInsightClient()..getError = ApiException('Server error', statusCode: 500);
      await _pump(tester, const CustomInsightReportScreen(reportId: 'r1'), fake: fake);

      expect(find.byKey(const Key('custom-report-deleted')), findsNothing);
      expect(find.byKey(const Key('custom-report-retry')), findsOneWidget);

      fake
        ..getError = null
        ..detail = _report(_json());
      await tester.tap(find.byKey(const Key('custom-report-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('custom-report-body')), findsOneWidget);
    });

    testWidgets('a refused report shows the refusal sentence and no figures', (tester) async {
      final fake = FakeCustomInsightClient()
        ..detail = _report(_json(status: 'refused', content: null, figures: false, instruction: 'Write a poem'));
      await _pump(tester, const CustomInsightReportScreen(reportId: 'r1'), fake: fake);

      expect(find.text(_refusal), findsOneWidget);
      expect(find.byKey(const Key('custom-report-body')), findsNothing);
      expect(find.byKey(const Key('custom-lang-mm')), findsNothing);
    });

    testWidgets('delete asks first, then goes back to the list', (tester) async {
      final fake = FakeCustomInsightClient()
        ..reports = [_report(_json(figures: false))]
        ..detail = _report(_json());
      await _pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open-report'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CustomInsightReportScreen(reportId: 'r1')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        fake: fake,
      );
      await tester.tap(find.byKey(const Key('open-report')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('custom-report-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this custom insight?'), findsOneWidget);
      // Cancel keeps it.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fake.deleted, isEmpty);

      await tester.tap(find.byKey(const Key('custom-report-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-insight-delete-confirm')));
      await tester.pumpAndSettle();

      expect(fake.deleted, ['r1']);
      expect(find.byKey(const Key('custom-report-body')), findsNothing);
      expect(find.byKey(const Key('open-report')), findsOneWidget);
    });

    testWidgets('while it leaves after a delete: no spinner, no deleted card, no second fetch', (tester) async {
      final fake = FakeCustomInsightClient()
        ..reports = [_report(_json(figures: false))]
        ..detail = _report(_json());
      await _pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open-report'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CustomInsightReportScreen(reportId: 'r1')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        fake: fake,
      );
      await tester.tap(find.byKey(const Key('open-report')));
      await tester.pumpAndSettle();
      expect(fake.getCalls, 1);

      await tester.tap(find.byKey(const Key('custom-report-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-insight-delete-confirm')));
      // The delete finishes and the route starts to leave: look at each frame.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('This custom insight was deleted.'), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(fake.deleted, ['r1']);
      expect(fake.getCalls, 1);
    });
  });

  group('Insights screen', () {
    InsightProvider recordingInsights(List<String> types) => InsightProvider(
          fetcher: ({required String language, required String insightType}) async {
            types.add(insightType);
            return Insight(
              id: 'i1',
              userId: 'u1',
              content: '## Summary\nEnglish text',
              generatedAt: DateTime.utc(2026, 11, 2),
            );
          },
        );

    testWidgets('insights_screen_custom_tab: third segment shows CustomInsightsTab; InsightProvider fetcher never gets "custom"',
        (tester) async {
      final types = <String>[];
      final fake = FakeCustomInsightClient()..reports = [_report(_json(id: 'a', figures: false))];
      await _pump(tester, InsightsScreen(), fake: fake, insights: recordingInsights(types));

      expect(find.byKey(const Key('insight-type-custom')), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      expect(find.byType(CustomInsightsTab), findsNothing);
      // Free weekly is locked, so the screen opened on monthly.
      expect(types, ['monthly']);

      await tester.tap(find.byKey(const Key('insight-type-custom')));
      await tester.pumpAndSettle();
      expect(find.byType(CustomInsightsTab), findsOneWidget);
      expect(find.byKey(const Key('custom-insight-item-a')), findsOneWidget);
      expect(find.byKey(const Key('custom-insight-new')), findsOneWidget);
      expect(types, ['monthly']);

      // Back to the others: they fetch again, never "custom".
      await tester.tap(find.byKey(const Key('insight-type-monthly')));
      await tester.pumpAndSettle();
      expect(find.byType(CustomInsightsTab), findsNothing);
      expect(types, ['monthly', 'monthly']);
      expect(types, isNot(contains('custom')));
    });

    testWidgets('report sections expand left-aligned without border lines; the selected tab is a filled pill',
        (tester) async {
      await _pump(tester, InsightsScreen(), fake: FakeCustomInsightClient(), insights: recordingInsights([]));

      final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile).first);
      expect(tile.expandedAlignment, Alignment.centerLeft);
      expect(tile.expandedCrossAxisAlignment, CrossAxisAlignment.start);
      expect(tile.shape, const Border());
      expect(tile.collapsedShape, const Border());

      await tester.tap(find.text('Summary'));
      await tester.pumpAndSettle();
      final body = tester.getRect(find.text('English text'));
      final card = tester.getRect(find.ancestor(of: find.byType(ExpansionTile).first, matching: find.byType(Card)));
      expect(body.left - card.left, lessThan(30), reason: 'expanded text is not left-aligned');

      BoxDecoration pill(String type) => tester
          .widget<AnimatedContainer>(
              find.descendant(of: find.byKey(Key('insight-type-$type')), matching: find.byType(AnimatedContainer)))
          .decoration! as BoxDecoration;
      final scheme = Theme.of(tester.element(find.byType(ExpansionTile).first)).colorScheme;
      expect(pill('monthly').color, scheme.primary);
      expect(pill('weekly').color, Colors.transparent);
    });

    for (final weekly in ['locked', 'included']) {
      testWidgets('without the custom argument a remembered Custom type falls back (weekly insight $weekly)', (tester) async {
        final types = <String>[];
        final insights = recordingInsights(types)..setInsightType('custom');
        await _pump(tester, InsightsScreen(), fake: FakeCustomInsightClient(), insights: insights, plan: _plan(weekly: weekly));

        expect(find.byType(CustomInsightsTab), findsNothing);
        // The usual rule: Free has no weekly insight, so monthly.
        final expected = weekly == 'locked' ? 'monthly' : 'weekly';
        expect(types, [expected]);
        expect(insights.insightType, expected);
      });
    }
    testWidgets('the /insights route opens on the Custom tab for the custom argument', (tester) async {
      final types = <String>[];
      final fake = FakeCustomInsightClient();
      await _pump(
        tester,
        const SizedBox(),
        fake: fake,
        insights: recordingInsights(types),
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: RouteSettings(name: settings.name, arguments: InsightsScreen.customTabArgument),
          builder: (_) => InsightsScreen(),
        ),
      );

      expect(InsightsScreen.customTabArgument, 'custom');
      expect(find.byType(CustomInsightsTab), findsOneWidget);
      expect(types, isEmpty);
    });
  });

  group('Notifications', () {
    test('push payload: ready with id round-trips with the full type', () {
      final payload = customInsightPayload('custom_insight_ready', 'report-1');
      expect(payload, 'custom_insight_ready|report-1');
      final parsed = parseCustomInsightPayload(payload)!;
      expect(parsed.type, 'custom_insight_ready');
      expect(parsed.goalId, 'report-1');
    });

    test('push payload: failed, and a missing id', () {
      expect(parseCustomInsightPayload(customInsightPayload('custom_insight_failed', 'x'))!.type, 'custom_insight_failed');
      final none = parseCustomInsightPayload(customInsightPayload('custom_insight_ready', null));
      expect(customInsightPayload('custom_insight_ready', null), 'custom_insight_ready|');
      expect(none!.type, 'custom_insight_ready');
      expect(none.goalId, isNull);
      // No separator at all still reads.
      expect(parseCustomInsightPayload('custom_insight_failed')!.goalId, isNull);
    });

    test('push payload: other pushes are not custom insight payloads', () {
      expect(customInsightPayload('goal_progress', 'g1'), isNull);
      expect(customInsightPayload(null, 'g1'), isNull);
      expect(parseCustomInsightPayload('3f2a9c0e-notification-id'), isNull);
      expect(parseCustomInsightPayload('ready|abc'), isNull);
      expect(parseCustomInsightPayload(null), isNull);
      expect(isCustomInsightPushType('custom_insight_ready'), isTrue);
      expect(isCustomInsightPushType('weekly_insights_generated'), isFalse);
    });

    test('notification_types_parse: custom_insight_ready / custom_insight_failed', () {
      AppNotification parse(String type) => AppNotification.fromJson({
            'id': 'n1',
            'user_id': 'u1',
            'type': type,
            'title': 't',
            'message': 'm',
            'goal_id': 'report-1',
            'goal_name': null,
            'currency': null,
            'created_at': '2026-11-02T08:15:00+00:00',
            'is_read': false,
          });

      final ready = parse('custom_insight_ready');
      expect(ready.type, NotificationType.custom_insight_ready);
      expect(ready.goalId, 'report-1');
      expect(parse('custom_insight_failed').type, NotificationType.custom_insight_failed);
      expect(NotificationType.custom_insight_ready.name, 'custom_insight_ready');
      // An unknown newer type still falls back instead of breaking the list.
      expect(parse('something_new').type, NotificationType.system_broadcast);
    });
  });

  test('every custom insight string exists in English and Myanmar', () {
    final en = AppLocalizations(const Locale('en'));
    final my = AppLocalizations(const Locale('my'));
    final getters = <String Function(AppLocalizations)>[
      (l) => l.insightTabCustom,
      (l) => l.customInsightNew,
      (l) => l.customInsightLockedTitle,
      (l) => l.customInsightLockedBody,
      (l) => l.customInsightUpgrade,
      (l) => l.customRangeLast30Days,
      (l) => l.customRangeLast3Months,
      (l) => l.customRangeThisYear,
      (l) => l.customRangePick,
      (l) => l.customInstructionLabel,
      (l) => l.customInstructionHint,
      (l) => l.customPresetWhereToSave,
      (l) => l.customPresetComparePrevious,
      (l) => l.customPresetBiggestChanges,
      (l) => l.customPresetBudgetsGoals,
      (l) => l.customInsightCreate,
      (l) => l.customInsightCreating,
      (l) => l.customInsightReused,
      (l) => l.customRangeTooShort,
      (l) => l.customRangeTooLong,
      (l) => l.customRangeInFuture,
      (l) => l.customRangeEndBeforeStart,
      (l) => l.customStatusPending,
      (l) => l.customStatusFailed,
      (l) => l.customStatusRefused,
      (l) => l.customErrorPending,
      (l) => l.customErrorAttempts,
      (l) => l.customErrorNoData,
      (l) => l.customInsightFullInsight,
      (l) => l.customReportIncome,
      (l) => l.customReportSpending,
      (l) => l.customReportNet,
      (l) => l.customReportVsPrevious,
      (l) => l.customReportNoPrevious,
      (l) => l.customReportTopSpending,
      (l) => l.customReportDeleted,
      (l) => l.customInsightDelete,
      (l) => l.customInsightDeleteConfirm,
      (l) => l.customInsightEmptyList,
      (l) => l.customInsightLoadMore,
    ];
    for (final get in getters) {
      final english = get(en);
      final myanmar = get(my);
      expect(english, isNot(startsWith('custom')), reason: english);
      expect(myanmar.trim(), isNotEmpty);
      expect(myanmar, isNot(startsWith('custom')), reason: myanmar);
      expect(myanmar, isNot(english), reason: english);
    }
    expect(en.customStatusRefused, _refusal);
  });

  group('Ko Toe Pwar', () {
    Finder pose(MascotPose p) =>
        find.byWidgetPredicate((w) => w is Mascot && w.pose == p, description: 'Mascot(${p.name})');
    final en = AppLocalizations(const Locale('en'));

    InsightProvider failing(Object error) =>
        InsightProvider(fetcher: ({required String language, required String insightType}) async => throw error);

    testWidgets('insight failed on the server: oops_sad above the message, with the retry', (tester) async {
      await _pump(tester, InsightsScreen(),
          fake: FakeCustomInsightClient(),
          insights: failing(ApiException('Server error', statusCode: 500)),
          plan: _plan(weekly: 'included'));
      expect(pose(MascotPose.oopsSad), findsOneWidget);
      expect(find.text(en.failedToLoadInsights), findsOneWidget);
      expect(tester.getBottomLeft(pose(MascotPose.oopsSad)).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.text(en.failedToLoadInsights)).dy));
      expect(find.text(en.tryAgain), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    });

    testWidgets('insight could not reach the server: offline_sad', (tester) async {
      await _pump(tester, InsightsScreen(),
          fake: FakeCustomInsightClient(),
          insights: failing(ApiException(en.errorNetworkUnreachable)),
          plan: _plan(weekly: 'included'));
      expect(pose(MascotPose.offlineSad), findsOneWidget);
      expect(pose(MascotPose.oopsSad), findsNothing);
    });

    testWidgets('no custom insights yet: idea_happy above the empty line', (tester) async {
      await _pump(tester, const Scaffold(body: CustomInsightsTab()), fake: FakeCustomInsightClient());
      expect(pose(MascotPose.ideaHappy), findsOneWidget);
      expect(tester.getSize(pose(MascotPose.ideaHappy)).height, inInclusiveRange(110, 140));
      expect(find.text(en.customInsightEmptyList), findsOneWidget);
    });

    testWidgets('custom report failed to load: oops_sad; offline: offline_sad', (tester) async {
      final fake = FakeCustomInsightClient()..getError = ApiException('Server error', statusCode: 500);
      await _pump(tester, const CustomInsightReportScreen(reportId: 'r1'), fake: fake);
      expect(pose(MascotPose.oopsSad), findsOneWidget);
      expect(find.byKey(const Key('custom-report-retry')), findsOneWidget);

      fake.getError = ApiException(en.errorRequestTimedOut);
      await tester.tap(find.byKey(const Key('custom-report-retry')));
      await tester.pumpAndSettle();
      expect(pose(MascotPose.offlineSad), findsOneWidget);
    });

    testWidgets('"Ko Toe Pwar\'s insights" titles use the never-"…" top-bar title', (tester) async {
      final my = AppLocalizations(const Locale('my'));
      await _pump(tester, InsightsScreen(),
          fake: FakeCustomInsightClient(), plan: _plan(weekly: 'included'), locale: const Locale('my'));
      expect(find.widgetWithText(AppBarTitle, my.aiInsights), findsOneWidget);

      final fake = FakeCustomInsightClient()..getError = ApiException('Server error', statusCode: 500);
      await _pump(tester, const CustomInsightReportScreen(reportId: 'r1'), fake: fake, locale: const Locale('my'));
      expect(find.widgetWithText(AppBarTitle, my.aiInsights), findsOneWidget);
    });

    testWidgets('a deleted report keeps its plain icon (not an error)', (tester) async {
      final fake = FakeCustomInsightClient()..getError = ApiException('Not found', statusCode: 404);
      await _pump(tester, const CustomInsightReportScreen(reportId: 'r1'), fake: fake);
      expect(find.byKey(const Key('custom-report-deleted')), findsOneWidget);
      expect(find.byType(Mascot), findsNothing);
    });

    for (final lang in ['en', 'my']) {
      testWidgets('$lang 360 px: the error and empty states fit', (tester) async {
        tester.view.physicalSize = const Size(360 * 3, 640 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        Future<void> pumpSmall(Widget home, {InsightProvider? insights, FakeCustomInsightClient? fake}) async {
          await _pump(tester, home,
              fake: fake ?? FakeCustomInsightClient(),
              insights: insights,
              plan: _plan(weekly: 'included'),
              locale: Locale(lang));
          // _pump sets its own big screen: shrink it back to the phone.
          tester.view.physicalSize = const Size(360 * 3, 640 * 3);
          tester.view.devicePixelRatio = 3;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(Mascot), findsOneWidget);
        }

        await pumpSmall(InsightsScreen(), insights: failing(ApiException('Server error', statusCode: 500)));
        await pumpSmall(const Scaffold(body: CustomInsightsTab()));
        await pumpSmall(const CustomInsightReportScreen(reportId: 'r1'),
            fake: FakeCustomInsightClient()..getError = ApiException('Server error', statusCode: 500));
      });
    }
  });
}

/// A client whose create always fails.
class _ThrowingCreate extends FakeCustomInsightClient {
  _ThrowingCreate(this.error);
  final Object error;

  @override
  Future<CustomInsightCreateResult> create(CustomInsightRequest request) async => throw error;
}
