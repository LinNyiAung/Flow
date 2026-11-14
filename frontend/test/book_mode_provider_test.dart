import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ONE MockClient for the file (ApiService binds its inner client once).
late http.Response Function(http.Request) _respond;
final _mock = MockClient((request) async => _respond(request));

Future<String?> _stored() async => (await SharedPreferences.getInstance()).getString(BookModeProvider.prefsKey);

void main() {
  late int modeChanges;

  BookModeProvider make() {
    modeChanges = 0;
    return BookModeProvider()..onModeChanged = () => modeChanges++;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
    ApiService.bookMode = BookMode.personal;
    ApiService.onNoFamily = null;
  });
  tearDown(() {
    ApiService.bookMode = BookMode.personal;
    ApiService.onNoFamily = null;
  });

  test('starts in Personal', () {
    final p = make();
    expect(p.mode, BookMode.personal);
    expect(p.isFamily, isFalse);
    expect(ApiService.bookMode, BookMode.personal);
  });

  test('setMode switches the API, persists the mode and reports the change once', () async {
    final p = make();
    var notified = 0;
    p.addListener(() => notified++);

    await p.setMode(BookMode.family);
    expect(p.mode, BookMode.family);
    expect(ApiService.bookMode, BookMode.family);
    expect(await _stored(), 'family');
    expect(modeChanges, 1);
    expect(notified, 1);

    await p.setMode(BookMode.family);
    expect(modeChanges, 1, reason: 'no change, no reset');

    await p.setMode(BookMode.personal);
    expect(ApiService.bookMode, BookMode.personal);
    expect(await _stored(), 'personal');
    expect(modeChanges, 2);
  });

  test('the mode persists across load()', () async {
    await make().setMode(BookMode.family);
    ApiService.bookMode = BookMode.personal;

    final next = make();
    await next.load();
    expect(next.mode, BookMode.family);
    expect(ApiService.bookMode, BookMode.family);
    expect(modeChanges, 1, reason: 'screens already built for Personal must reset');
  });

  test('load() with nothing stored stays Personal, quietly', () async {
    final p = make();
    await p.load();
    expect(p.mode, BookMode.personal);
    expect(modeChanges, 0);
  });

  test('reset() returns to Personal and the next load() re-reads the device', () async {
    SharedPreferences.setMockInitialValues({BookModeProvider.prefsKey: 'family'});
    final p = make();
    await p.load();
    expect(p.mode, BookMode.family);

    p.reset();
    expect(p.mode, BookMode.personal);
    expect(ApiService.bookMode, BookMode.personal);
    expect(await _stored(), 'family', reason: 'the device keeps its choice');

    await p.load();
    expect(p.mode, BookMode.family);
  });

  test('a load() that finishes after reset() is dropped', () async {
    SharedPreferences.setMockInitialValues({BookModeProvider.prefsKey: 'family'});
    final p = make();
    final loading = p.load();
    p.reset();
    await loading;
    expect(p.mode, BookMode.personal);
    expect(ApiService.bookMode, BookMode.personal);
  });

  test('a load() that finishes after setMode() does not undo it', () async {
    SharedPreferences.setMockInitialValues({BookModeProvider.prefsKey: 'family'});
    final p = make();
    final loading = p.load();
    await p.setMode(BookMode.personal);
    await loading;
    expect(p.mode, BookMode.personal);
  });

  group('no_family', () {
    test('a no_family response flips Family mode to Personal', () async {
      final p = make();
      await p.setMode(BookMode.family);
      modeChanges = 0;
      var fired = 0;
      ApiService.onNoFamily = () {
        fired++;
        p.fallBackToPersonal();
      };
      _respond = (_) => http.Response(
          jsonEncode({
            'detail': {'code': 'no_family', 'message': "You're not in a family."}
          }),
          409,
          headers: {'content-type': 'application/json'});

      final error = await http.runWithClient(() async {
        try {
          await ApiService.getTransactions();
          return null;
        } catch (e) {
          return e;
        }
      }, () => _mock);

      expect((error as ApiException).code, 'no_family');
      expect(fired, 1);
      expect(p.mode, BookMode.personal);
      expect(ApiService.bookMode, BookMode.personal);
      expect(modeChanges, 1);
      await pumpEventQueue();
      expect(await _stored(), 'personal');
    });

    test('fallBackToPersonal says whether it switched', () async {
      final p = make();
      expect(p.fallBackToPersonal(), isFalse);
      expect(modeChanges, 0);
      await p.setMode(BookMode.family);
      expect(p.fallBackToPersonal(), isTrue);
      expect(p.mode, BookMode.personal);
      expect(p.fallBackToPersonal(), isFalse);
    });
  });

  group('openInBook', () {
    Future<void> pumpButton(WidgetTester tester, BookModeProvider p, Future<void> Function(BuildContext) onTap) =>
        tester.pumpWidget(ChangeNotifierProvider.value(
          value: p,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(onPressed: () => onTap(context), child: const Text('open')),
            ),
          ),
        ));

    testWidgets('a family notice switches to Family before opening', (tester) async {
      final p = make();
      final seen = <String>[];
      p.onModeChanged = () => seen.add('reset:${p.mode.name}');
      await pumpButton(
          tester, p, (context) => openInBook(context, family: true, open: () => seen.add('open:${p.mode.name}')));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(seen, ['reset:family', 'open:family']);
      expect(ApiService.bookMode, BookMode.family);
    });

    testWidgets('already in Family: opens without a reset', (tester) async {
      final p = make();
      await tester.runAsync(() => p.setMode(BookMode.family));
      modeChanges = 0;
      var opened = 0;
      await pumpButton(tester, p, (context) => openInBook(context, family: true, open: () => opened++));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(modeChanges, 0);
    });

    testWidgets('a personal notice tapped in Family mode switches to Personal before opening', (tester) async {
      final p = make();
      await tester.runAsync(() => p.setMode(BookMode.family));
      final seen = <String>[];
      p.onModeChanged = () => seen.add('reset:${p.mode.name}');
      await pumpButton(
          tester, p, (context) => openInBook(context, family: false, open: () => seen.add('open:${p.mode.name}')));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(seen, ['reset:personal', 'open:personal']);
      expect(ApiService.bookMode, BookMode.personal);
    });

    testWidgets('a personal notice in Personal mode opens without a reset', (tester) async {
      final p = make();
      var opened = 0;
      await pumpButton(tester, p, (context) => openInBook(context, family: false, open: () => opened++));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(p.mode, BookMode.personal);
      expect(modeChanges, 0);
    });
  });
}
