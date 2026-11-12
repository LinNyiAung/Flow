import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/goals/goal_detail_screen.dart';
import 'package:frontend/screens/subscription/subscription_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/accepted_payments.dart';
import 'package:frontend/widgets/mascot.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _pose(MascotPose pose) =>
    find.byWidgetPredicate((w) => w is Mascot && w.pose == pose, description: 'Mascot(${pose.name})');

final _now = DateTime.now();

Goal _goal({GoalStatus status = GoalStatus.active}) => Goal(
      id: 'g1',
      userId: 'u1',
      name: 'Emergency fund',
      targetAmount: 8000,
      currentAmount: status == GoalStatus.achieved ? 8000 : 1000,
      goalType: GoalType.savings,
      status: status,
      progressPercentage: status == GoalStatus.achieved ? 100 : 12.5,
      createdAt: _now,
      updatedAt: _now,
      achievedAt: status == GoalStatus.achieved ? _now : null,
      currency: Currency.usd,
    );

PlanStatus _status() => PlanStatus(
      plan: Plan.free,
      catalog: {
        Plan.free: {PlanFeature.chat: const CatalogLimit(mode: 'counted', quota: 7, period: 'week')},
        Plan.plus: {PlanFeature.chat: const CatalogLimit(mode: 'counted', quota: 123, period: 'month')},
        Plan.pro: {PlanFeature.chat: const CatalogLimit(mode: 'counted', quota: 456, period: 'month')},
      },
    );

/// A Plus user until a date: the page shows "Your plan".
class _PlusUser extends AuthProvider {
  @override
  bool get isPaid => true;
  @override
  Plan get plan => Plan.plus;
  @override
  bool get isTrial => false;
  @override
  bool get hasClaimedFreeTrial => true;
  @override
  DateTime? get subscriptionExpiresAt => _now.add(const Duration(days: 20));
}

Future<void> _pump(WidgetTester tester, Widget home,
    {String lang = 'en', double width = 390, AuthProvider? auth}) async {
  // A token, so the plan (and the upgrade buttons and KPay/WavePay row) loads.
  SharedPreferences.setMockInitialValues({'access_token': 'tok'});
  tester.view.physicalSize = Size(width * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => auth ?? AuthProvider()),
      ChangeNotifierProvider(create: (_) => PlanProvider(loader: () async => _status())),
      ChangeNotifierProvider(create: (_) => GoalProvider()),
      ChangeNotifierProvider(create: (_) => TransactionProvider()),
    ],
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
  final en = AppLocalizations(const Locale('en'));

  // The owner doesn't want the mascot on the plans screen.
  testWidgets('Upgrade page (Free): no mascot; KPay/WavePay row unchanged', (tester) async {
    await _pump(tester, SubscriptionScreen());
    expect(find.text(en.comparePlans), findsOneWidget);
    expect(find.byType(Mascot), findsNothing);
    expect(find.byType(AcceptedPayments), findsOneWidget);
  });

  testWidgets('"Your plan" for a paid user: no mascot', (tester) async {
    await _pump(tester, SubscriptionScreen(), auth: _PlusUser());
    expect(find.text(en.yourPlanTitle), findsOneWidget);
    expect(find.byType(Mascot), findsNothing);
  });

  testWidgets('an achieved goal: trophy_joy in the goal detail header', (tester) async {
    await _pump(tester, GoalDetailScreen(goal: _goal(status: GoalStatus.achieved)));
    expect(_pose(MascotPose.trophyJoy), findsOneWidget);
    expect(tester.getSize(_pose(MascotPose.trophyJoy)).height, inInclusiveRange(100, 140));
    expect(find.text(en.achieved.toUpperCase()), findsOneWidget);
  });

  testWidgets('an active goal: no trophy', (tester) async {
    await _pump(tester, GoalDetailScreen(goal: _goal()));
    expect(find.byType(Mascot), findsNothing);
  });

  for (final lang in ['en', 'my']) {
    testWidgets('$lang 360 px: upgrade page and achieved goal do not overflow', (tester) async {
      await _pump(tester, SubscriptionScreen(), lang: lang, width: 360);
      expect(tester.takeException(), isNull);
      await _pump(tester, GoalDetailScreen(goal: _goal(status: GoalStatus.achieved)), lang: lang, width: 360);
      expect(tester.takeException(), isNull);
    });
  }
}
