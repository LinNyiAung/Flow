import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/app_bar_title.dart';

Future<void> _pumpBar(WidgetTester tester, String title, {int actions = 1}) async {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    // The app theme's bar: 64 high, 22 px titles (without its Google Fonts).
    theme: ThemeData(appBarTheme: const AppBarTheme(toolbarHeight: 64, titleTextStyle: TextStyle(fontSize: 22))),
    home: Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.menu_rounded), onPressed: () {}),
        title: AppBarTitle(title),
        actions: [
          for (var i = 0; i < actions; i++) IconButton(icon: const Icon(Icons.notifications_rounded), onPressed: () {}),
        ],
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  final my = AppLocalizations(const Locale('my'));
  final en = AppLocalizations(const Locale('en'));

  testWidgets('a title that fits stays one line at the theme size', (tester) async {
    await _pumpBar(tester, en.budgets);
    final text = tester.widget<Text>(find.text(en.budgets));
    expect(text.maxLines, 1);
    expect(tester.renderObject<RenderParagraph>(find.text(en.budgets)).text.style?.fontSize, 22);
  });

  for (final title in [
    my.financialGoals,
    my.outflowAnalytics,
    my.inflowAnalytics,
    my.allTransactionsTitle,
    my.financialReports,
  ]) {
    testWidgets('Myanmar 360: "$title" shows in full inside the bar', (tester) async {
      await _pumpBar(tester, title, actions: 2);
      expect(tester.takeException(), isNull);
      final finder = find.text(title);
      expect(finder, findsOneWidget);
      expect(tester.renderObject<RenderParagraph>(finder).didExceedMaxLines, isFalse);
      final bar = tester.getRect(find.byType(AppBar));
      final rect = tester.getRect(finder);
      expect(rect.top, greaterThanOrEqualTo(bar.top));
      expect(rect.bottom, lessThanOrEqualTo(bar.bottom));
      expect(rect.right, lessThanOrEqualTo(360 - 2 * 48));
    });
  }
}
