// E2E harness: runs the REAL app (app.main()) on a device against the local
// test backend, collects every framework error / RenderFlex overflow /
// uncaught async exception per test, and offers small robust helpers.
//
// Output lines (grep the `flutter test` log for them):
//   E2E_ISSUE|<test>|<kind>|<step>|<screen>|<message>
//   E2E_RESULT|<test>|PASS|FAIL|<n issues>
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart' as app;
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accounts.dart';

/// English / Myanmar strings, straight from the app's own localization table.
final L = AppLocalizations(const Locale('en'));
final LM = AppLocalizations(const Locale('my'));

/// Backend as seen from the emulator.
const String kApiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8765',
);

/// Host helper that serves the captured e-mail outbox (outbox_server.py).
const String kOutboxUrl = String.fromEnvironment(
  'OUTBOX_URL',
  defaultValue: 'http://10.0.2.2:8766/outbox',
);

late WidgetTester T;

/// The local uvicorn closes idle keep-alive connections after 5 s while
/// dart:io keeps them for 15 s, so the app's shared http.Client randomly
/// reuses a dead socket ("Connection closed before full header was
/// received"). That is reported as a robustness finding; to keep the other
/// flows deterministic the suite shortens the idle timeout to 3 s.
/// Pass --dart-define=E2E_RAW_HTTP=true to run without this accommodation.
class _ShortIdleHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final c = super.createHttpClient(context);
    c.idleTimeout = const Duration(seconds: 3);
    return c;
  }
}

IntegrationTestWidgetsFlutterBinding initBinding() {
  final b = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  b.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  if (!const bool.fromEnvironment('E2E_RAW_HTTP')) {
    HttpOverrides.global = _ShortIdleHttpOverrides();
  }
  return b;
}

bool _found(Finder f) {
  try {
    return f.evaluate().isNotEmpty;
  } on StateError {
    return false; // e.g. `.first` of an empty finder
  }
}

class Issue {
  final String test;
  final String kind; // FLUTTER_ERROR | OVERFLOW | ASYNC_ERROR | APP_BUG
  final String step;
  final String screen;
  final String message;
  Issue(this.test, this.kind, this.step, this.screen, this.message);

  String get line =>
      'E2E_ISSUE|$test|$kind|$step|$screen|${message.replaceAll('\n', ' ⏎ ')}';
}

class E2E {
  static String test = '';
  static String _step = '';
  static String screen = '';
  static final List<Issue> issues = [];
  static final Set<String> _seen = {};

  static String get step => _step;

  static void stepTo(String s) {
    _step = s;
    // ignore: avoid_print
    print('E2E_STEP|$test|$s');
  }

  static void begin(String name) {
    test = name;
    _step = 'start';
    screen = '';
    issues.clear();
    _seen.clear();
  }

  static void add(String kind, String message) {
    final key = '$kind|${message.length > 300 ? message.substring(0, 300) : message}';
    if (!_seen.add(key)) return;
    final issue = Issue(test, kind, _step, screen, message);
    issues.add(issue);
    // ignore: avoid_print
    print(issue.line);
  }

  static void recordFlutterError(FlutterErrorDetails details) {
    final text = details.exceptionAsString();
    final kind = text.contains('overflowed') ? 'OVERFLOW' : 'FLUTTER_ERROR';
    var full = details.toString();
    // Keep the useful head (exception + "relevant error-causing widget").
    final lines = full.split('\n');
    final keep = <String>[];
    for (final l in lines) {
      if (l.trim().isEmpty) continue;
      keep.add(l.trim());
      if (keep.length >= 14) break;
    }
    final stackTop = details.stack == null
        ? ''
        : ' STACK: ${_appFrames(details.stack!)}';
    add(kind, '${keep.join(' | ')}$stackTop');
  }

  static void recordAsync(Object error, StackTrace stack) {
    final text = '$error';
    if (text.contains('Failed to load font with url')) {
      // google_fonts runtime fetch from fonts.gstatic.com failed (emulator
      // internet access) — reported once as a robustness note, not a failure.
      _note('FONT_FETCH', text.split(':').take(2).join(':'));
      return;
    }
    add('ASYNC_ERROR', '$text STACK: ${_appFrames(stack)}');
  }

  static final Set<String> _notes = {};
  static void _note(String kind, String msg) {
    if (!_notes.add(kind)) return;
    // ignore: avoid_print
    print('E2E_NOTE|$test|$kind|$_step|$screen|$msg');
  }

  /// First few frames that point into the app (package:frontend/...).
  static String _appFrames(StackTrace st) {
    final frames = st
        .toString()
        .split('\n')
        .where((l) => l.contains('package:frontend/'))
        .take(4)
        .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
        .toList();
    if (frames.isEmpty) {
      return st.toString().split('\n').take(3).join(' / ');
    }
    return frames.join(' / ');
  }
}

/// Records a genuine app misbehaviour without aborting the test.
void appBug(String description) => E2E.add('APP_BUG', description);

/// Soft check: records [description] as an app bug when [ok] is false.
bool check(bool ok, String description) {
  if (!ok) appBug(description);
  return ok;
}

void step(String s) => E2E.stepTo(s);

/// One end-to-end test. Starts the real app logged out, collects every
/// error while [body] runs, fails the test if any issue was recorded.
void e2eTest(
  String description,
  Future<void> Function(WidgetTester t) body, {
  Duration timeout = const Duration(minutes: 8),
  bool skip = false,
}) {
  testWidgets(description, (tester) async {
    T = tester;
    E2E.begin(description);
    final origOnError = FlutterError.onError;
    final origPlatformOnError = PlatformDispatcher.instance.onError;
    FlutterError.onError = E2E.recordFlutterError;
    PlatformDispatcher.instance.onError = (e, st) {
      E2E.recordAsync(e, st);
      return true;
    };

    final done = Completer<void>();
    Object? bodyError;
    StackTrace? bodyStack;
    runZonedGuarded(() async {
      try {
        await startApp();
        await body(tester);
        // Let late async work (e.g. setState after an await) surface.
        await pumpFor(const Duration(milliseconds: 800));
      } catch (e, st) {
        bodyError = e;
        bodyStack = st;
      } finally {
        if (!done.isCompleted) done.complete();
      }
    }, E2E.recordAsync);
    await done.future;

    FlutterError.onError = origOnError;
    PlatformDispatcher.instance.onError = origPlatformOnError;

    final failed = bodyError != null || E2E.issues.isNotEmpty;
    // ignore: avoid_print
    print('E2E_RESULT|$description|${failed ? 'FAIL' : 'PASS'}|'
        '${E2E.issues.length} issues'
        '${bodyError != null ? '|TEST_ABORTED at step "${E2E.step}" on "${E2E.screen}": ${bodyError.toString().split('\n').take(6).join(' ')}' : ''}');
    if (bodyError != null) {
      Error.throwWithStackTrace(bodyError!, bodyStack!);
    }
    if (E2E.issues.isNotEmpty) {
      fail('${E2E.issues.length} issue(s) recorded:\n'
          '${E2E.issues.map((i) => i.line).join('\n')}');
    }
  }, timeout: Timeout(timeout), skip: skip, semanticsEnabled: false);
}

// ─────────────────────────────── app lifecycle ──────────────────────────────

/// Clears local state (token, language, theme, ...) and boots the real app.
Future<void> startApp({String? language}) async {
  step('boot app');
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  if (language != null) {
    await prefs.setString('selected_language', language);
  }
  app.main();
  await waitFor(find.byType(LoginScreen), timeout: const Duration(seconds: 60),
      reason: 'login screen after boot');
}

// ─────────────────────────────── waiting / pumping ───────────────────────────

Future<void> pumpFor(Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await T.pump(const Duration(milliseconds: 50));
  }
  _updateScreen();
}

Future<void> settle([int ms = 600]) => pumpFor(Duration(milliseconds: ms));

/// Pumps until [f] finds something. Throws (test bug / blocked flow) unless
/// [orNull] — then returns false.
Future<bool> waitFor(
  Finder f, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
  bool orNull = false,
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    await T.pump(const Duration(milliseconds: 100));
    if (_found(f)) {
      _updateScreen();
      return true;
    }
    if (DateTime.now().isAfter(end)) break;
  }
  _updateScreen();
  if (orNull) return false;
  throw TestFailure(
      'Timed out after ${timeout.inSeconds}s waiting for ${reason ?? f.describeMatch(Plurality.one)} '
      '(screen: ${E2E.screen}). Visible texts: ${visibleTexts().take(40).join(' | ')}');
}

Future<bool> waitGone(Finder f,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await T.pump(const Duration(milliseconds: 100));
    if (f.evaluate().isEmpty) {
      _updateScreen();
      return true;
    }
  }
  _updateScreen();
  return false;
}

/// Waits until any of [finders] matches; returns its index or -1.
Future<int> waitAny(List<Finder> finders,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    await T.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < finders.length; i++) {
      if (_found(finders[i])) {
        _updateScreen();
        return i;
      }
    }
    if (DateTime.now().isAfter(end)) return -1;
  }
}

/// Waits for an app behaviour; records an APP_BUG (and returns false) if it
/// never shows up.
Future<bool> expectSoon(Finder f, String bugIfMissing,
    {Duration timeout = const Duration(seconds: 15)}) async {
  final ok = await waitFor(f, timeout: timeout, orNull: true);
  if (!ok) {
    appBug('$bugIfMissing (visible: ${visibleTexts().take(25).join(' | ')})');
  }
  return ok;
}

// ─────────────────────────────── screen tracking ─────────────────────────────

void _updateScreen() {
  try {
    final bars = find.byType(AppBar).evaluate().toList();
    if (bars.isNotEmpty) {
      final bar = bars.last.widget as AppBar;
      final title = bar.title;
      String? name;
      if (title is Text) name = title.data;
      name ??= find
          .descendant(
              of: find.byWidget(bar), matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .firstOrNull;
      E2E.screen = name ?? 'AppBar(?)';
      return;
    }
    if (find.byType(LoginScreen).evaluate().isNotEmpty) {
      E2E.screen = 'Login';
      return;
    }
    E2E.screen = 'no-appbar';
  } catch (_) {}
}

List<String> visibleTexts() {
  final out = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final s = w.data ?? w.textSpan?.toPlainText();
    if (s != null && s.trim().isNotEmpty) out.add(s.trim());
  }
  for (final e in find.byType(RichText).evaluate()) {
    final s = (e.widget as RichText).text.toPlainText();
    if (s.trim().isNotEmpty && !out.contains(s.trim())) out.add(s.trim());
  }
  return out;
}

bool hasText(String s) => find.text(s).evaluate().isNotEmpty;
bool hasTextContaining(String s) =>
    find.textContaining(s).evaluate().isNotEmpty;

// ─────────────────────────────── interaction ─────────────────────────────────

Future<void> ensureVisible(Finder f) async {
  try {
    await T.ensureVisible(f.first);
    await T.pump(const Duration(milliseconds: 250));
  } catch (_) {}
}

Future<void> tap(Finder f,
    {Duration timeout = const Duration(seconds: 20),
    bool visible = true,
    int settleMs = 500}) async {
  await waitFor(f, timeout: timeout);
  if (visible) await ensureVisible(f);
  if (!_found(f.hitTestable())) {
    // Usually a SnackBar (or a closing sheet) covering the target.
    try {
      for (final e in find.byType(ScaffoldMessenger).evaluate()) {
        (e as StatefulElement).state is ScaffoldMessengerState
            ? (e.state as ScaffoldMessengerState).hideCurrentSnackBar()
            : null;
      }
    } catch (_) {}
    final end = DateTime.now().add(const Duration(seconds: 4));
    while (!_found(f.hitTestable()) && DateTime.now().isBefore(end)) {
      await T.pump(const Duration(milliseconds: 100));
    }
    if (!_found(f.hitTestable())) {
      final s = _mainScrollable();
      if (s != null) {
        await T.drag(s, const Offset(0, -150), warnIfMissed: false);
        await settle(400);
      }
    }
  }
  final target = _found(f.hitTestable()) ? f.hitTestable().first : f.first;
  await T.tap(target, warnIfMissed: false);
  await settle(settleMs);
}

/// Finds a button of type [T] (or a subclass, e.g. TextButton.icon) with [text].
Finder buttonWithText<B extends Widget>(String text) => find.ancestor(
    of: find.text(text), matching: find.byWidgetPredicate((w) => w is B)).first;

Future<void> tapText(String text, {int settleMs = 500, Duration timeout = const Duration(seconds: 20)}) =>
    tap(find.text(text), settleMs: settleMs, timeout: timeout);
Future<void> tapIcon(IconData icon, {int settleMs = 500}) =>
    tap(find.byIcon(icon), settleMs: settleMs);
Future<void> tapKey(String key, {int settleMs = 300}) =>
    tap(find.byKey(ValueKey(key)), settleMs: settleMs);
Future<void> tapTooltip(String tooltip, {int settleMs = 500}) =>
    tap(find.byTooltip(tooltip), settleMs: settleMs);

Future<void> enter(Finder f, String text) async {
  await waitFor(f);
  await ensureVisible(f);
  TextEditingController? ctl() {
    final e = find.descendant(of: f.first, matching: find.byType(EditableText), matchRoot: true);
    if (e.evaluate().isEmpty) return null;
    return T.widget<EditableText>(e.first).controller;
  }

  for (var attempt = 0; attempt < 2; attempt++) {
    await T.enterText(f.first, text);
    await settle(300);
    final c = ctl();
    if (c == null || c.text == text) return;
    // The test text-input connection sometimes stays attached to a
    // previously focused field: refocus and retry.
    await hideKeyboard();
    await T.tap(f.first, warnIfMissed: false);
    await settle(300);
  }
  final c = ctl();
  if (c != null && c.text != text) {
    c.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    await settle(300);
  }
}

Future<void> hideKeyboard() async {
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(400);
}

Future<void> back() async {
  final nav = find.byType(Navigator);
  final state = T.state<NavigatorState>(nav.last);
  await state.maybePop();
  await settle(700);
}

/// Scrolls the main (largest vertical) scrollable until [f] is found.
Future<bool> scrollTo(Finder f,
    {int maxSwipes = 25, double dy = -300, Finder? scrollable}) async {
  for (var i = 0; i < maxSwipes; i++) {
    if (f.evaluate().isNotEmpty) {
      await ensureVisible(f);
      return true;
    }
    final s = scrollable ?? _mainScrollable();
    if (s == null) return false;
    try {
      await T.drag(s, Offset(0, dy), warnIfMissed: false);
    } catch (_) {}
    await settle(350);
  }
  if (f.evaluate().isNotEmpty) {
    await ensureVisible(f);
    return true;
  }
  return false;
}

Finder? _mainScrollable() {
  final candidates = find.byType(Scrollable).hitTestable().evaluate().toList();
  Element? best;
  double bestArea = 0;
  for (final e in candidates) {
    final s = e.widget as Scrollable;
    if (s.axisDirection != AxisDirection.down &&
        s.axisDirection != AxisDirection.up) {
      continue;
    }
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.hasSize) continue;
    final area = box.size.width * box.size.height;
    if (area > bestArea) {
      bestArea = area;
      best = e;
    }
  }
  if (best == null) return null;
  final target = best;
  return find.byElementPredicate((e) => e == target);
}

// ─────────────────────────────── app flows ───────────────────────────────────

Future<void> login(Account a, {bool expectHome = true}) async {
  step('login ${a.key}');
  await waitFor(find.byType(LoginScreen), timeout: const Duration(seconds: 40));
  final fields = find.byType(TextFormField);
  await enter(fields.at(0), a.email);
  await enter(fields.at(1), a.password);
  await hideKeyboard();
  await tap(find.byType(FilledButton).first);
  if (expectHome) {
    for (var attempt = 0; attempt < 3; attempt++) {
      final r = await waitAny([find.byType(HomeScreen), find.textContaining('Could not reach the server')],
          timeout: const Duration(seconds: 60));
      if (r == 0) break;
      if (r == 1) {
        // Stale keep-alive connection dropped by the server (see report).
        // ignore: avoid_print
        print('E2E_INFO|${E2E.test}|login hit "${visibleTexts().firstWhere((x) => x.contains('Could not reach'), orElse: () => '')}" — retrying');
        await settle(1000);
        await tap(find.byType(FilledButton).first);
        continue;
      }
      throw TestFailure('Timed out waiting for home after login (visible: ${visibleTexts().take(20).join(' | ')})');
    }
    await waitFor(find.byType(HomeScreen), timeout: const Duration(seconds: 30), reason: 'home after login');
    await settle(1500);
  }
}

Future<void> openDrawer() async {
  await tap(find.byIcon(Icons.menu_rounded).last);
  await settle(500);
}

/// Opens a drawer destination by its (localized) label.
Future<void> drawerGo(String label) async {
  step('drawer → $label');
  await openDrawer();
  final inDrawer = find.descendant(of: find.byType(Drawer), matching: find.text(label));
  await scrollTo(inDrawer, scrollable: find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)).first);
  await tap(inDrawer);
  await settle(1200);
}

Future<void> logout({AppLocalizations? l}) async {
  final loc = l ?? L;
  step('logout');
  await openDrawer();
  final row = find.descendant(of: find.byType(Drawer), matching: find.text(loc.drawerLogout));
  await scrollTo(row, scrollable: find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)).first);
  await tap(row);
  await tap(find.widgetWithText(FilledButton, loc.drawerLogout));
  await waitFor(find.byType(LoginScreen), timeout: const Duration(seconds: 30));
}

/// Goes back to Home (root) by popping everything.
Future<void> goHome() async {
  final nav = T.state<NavigatorState>(find.byType(Navigator).first);
  nav.popUntil((r) => r.isFirst);
  await settle(1000);
  await waitFor(find.byType(HomeScreen), timeout: const Duration(seconds: 20));
}

// ─────────────────────────────── host helpers ────────────────────────────────

/// Reads the captured e-mails (one JSON object per line).
Future<List<Map<String, dynamic>>> readOutbox() async {
  final r = await http.get(Uri.parse(kOutboxUrl)).timeout(const Duration(seconds: 10));
  return const LineSplitter()
      .convert(utf8.decode(r.bodyBytes))
      .where((l) => l.trim().isNotEmpty)
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .toList();
}

/// Latest e-mail text sent to [email] whose text matches [contains].
Future<String?> latestMailTo(String email, {String contains = ''}) async {
  final mails = await readOutbox();
  for (final m in mails.reversed) {
    final args = (m['args'] as List?) ?? const [];
    final text = args.isEmpty ? '' : args.first.toString();
    if (text.contains('To: $email') && text.contains(contains)) return text;
  }
  return null;
}

/// Direct API helper (used only to arrange/verify state, never to replace UI).
Future<String> apiToken(Account a) async {
  final r = await http.post(Uri.parse('$kApiBase/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': a.email, 'password': a.password}));
  if (r.statusCode != 200) {
    throw TestFailure('API login failed for ${a.email}: ${r.statusCode} ${r.body}');
  }
  return (jsonDecode(r.body) as Map)['access_token'] as String;
}

Future<dynamic> apiGet(String token, String path) async {
  final r = await http.get(Uri.parse('$kApiBase$path'),
      headers: {'Authorization': 'Bearer $token'});
  return jsonDecode(utf8.decode(r.bodyBytes));
}
