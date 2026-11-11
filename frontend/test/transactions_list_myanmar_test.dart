import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/screens/transactions/transactions_list_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/date_format.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotifications extends NotificationProvider {
  @override
  Future<void> fetchUnreadCount() async {}
}

/// No server here: the list loads empty (the request fails), which is enough
/// for the filter bar and the count line.
Future<void> _pump(WidgetTester tester, Locale locale) async {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<NotificationProvider>(create: (_) => _FakeNotifications()),
      ChangeNotifierProvider<PlanProvider>(create: (_) => PlanProvider()),
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
      home: TransactionsListScreen(
        initialStartDate: DateTime(2026, 11, 10),
        initialEndDate: DateTime(2026, 11, 10),
        initialCurrency: Currency.mmk,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _chipWithIcon(IconData icon) => find.ancestor(of: find.byIcon(icon), matching: find.byType(InkWell)).first;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final my = AppLocalizations(const Locale('my'));

  testWidgets('English: the date chip uses the app date format', (tester) async {
    await _pump(tester, const Locale('en'));
    // "10 Nov", plus the year once 2026 is over.
    final day = AppDates.compactDayIn(DateTime(2026, 11, 10));
    expect(day, startsWith('10 Nov'));
    expect(find.text('$day – $day'), findsOneWidget);
  });

  testWidgets('Myanmar 360: all three filters are on screen', (tester) async {
    await _pump(tester, const Locale('my'));
    expect(tester.takeException(), isNull);
    for (final icon in [Icons.swap_vert_rounded, Icons.event_rounded, Icons.currency_exchange_rounded]) {
      final rect = tester.getRect(_chipWithIcon(icon));
      expect(rect.left, greaterThanOrEqualTo(0), reason: '$icon');
      expect(rect.right, lessThanOrEqualTo(360), reason: '$icon');
    }
  });

  testWidgets('Myanmar 360: the date chip uses Myanmar month names', (tester) async {
    await _pump(tester, const Locale('my'));
    expect(find.textContaining('Nov'), findsNothing);
    final day = AppDates.compactDayIn(DateTime(2026, 11, 10), locale: 'my');
    expect(day, startsWith('၁၀ နို'));
    expect(find.text('$day – $day'), findsOneWidget);
  });

  testWidgets('Myanmar 360: the count line is not cut short', (tester) async {
    await _pump(tester, const Locale('my'));
    final count = find.text('0 ${my.transactionsCountSuffix}');
    expect(count, findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(count).didExceedMaxLines, isFalse);
  });
}
