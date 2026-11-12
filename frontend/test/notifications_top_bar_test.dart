import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/notifications_top_bar.dart';

Future<int> _pump(WidgetTester tester, Locale locale, double width, {bool unread = true}) async {
  tester.view.physicalSize = Size(width * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  var taps = 0;
  final l = AppLocalizations(locale);
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('my')],
    home: Scaffold(
      appBar: NotificationsTopBar(
        title: l.notifications,
        markAllReadLabel: l.markAllRead,
        showMarkAllRead: unread,
        onMarkAllRead: () => taps++,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  if (unread) await tester.tap(find.byKey(const Key('mark-all-read')).hitTestable());
  return taps;
}

void _expectTitleInFull(WidgetTester tester, String title, double width) {
  expect(tester.takeException(), isNull);
  final f = find.text(title);
  expect(f, findsOneWidget);
  expect(tester.renderObject<RenderParagraph>(f).didExceedMaxLines, isFalse, reason: 'title cut off');
  final rect = tester.getRect(f);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(width));
  final button = tester.getRect(find.byKey(const Key('mark-all-read')));
  expect(rect.right, lessThanOrEqualTo(button.left), reason: 'title runs under the button');
}

void main() {
  final en = AppLocalizations(const Locale('en'));
  final my = AppLocalizations(const Locale('my'));

  // The test font draws every glyph as a full square (about twice Manrope's
  // width), so "room for the label" is checked on a wide screen.
  testWidgets('room to spare: the labelled button, and the full title', (tester) async {
    final taps = await _pump(tester, const Locale('en'), 700);
    expect(find.text(en.markAllRead), findsOneWidget);
    _expectTitleInFull(tester, en.notifications, 700);
    expect(taps, 1);
  });

  testWidgets('Myanmar 360: an icon button with a tooltip; the title is not cut off', (tester) async {
    final taps = await _pump(tester, const Locale('my'), 360);
    expect(find.text(my.markAllRead), findsNothing);
    expect(find.byTooltip(my.markAllRead), findsOneWidget);
    _expectTitleInFull(tester, my.notifications, 360);
    expect(taps, 1);
  });

  testWidgets('nothing unread: no button', (tester) async {
    await _pump(tester, const Locale('my'), 360, unread: false);
    expect(find.byKey(const Key('mark-all-read')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
