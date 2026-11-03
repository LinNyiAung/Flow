import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/voice_image_models.dart';
import 'package:frontend/screens/transactions/voice_extraction.dart';
import 'package:frontend/screens/transactions/voice_retry_hint.dart';
import 'package:frontend/services/localization_service.dart';

// 2026-11-03 12:00:00 UTC, as unix seconds.
final _expiry = DateTime.utc(2026, 11, 3, 12);
final _token = '${_expiry.millisecondsSinceEpoch ~/ 1000}.signature';

VoiceExtraction _extraction({String? token}) => VoiceExtraction(
      TranscriptionResult(transcription: 'coffee 3 dollars', voiceToken: token),
      extractor: (text, {voiceToken}) async => throw UnimplementedError(),
    );

Future<void> _pump(WidgetTester tester, VoiceExtraction extraction, DateTime Function() clock) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('my')],
      home: Scaffold(body: VoiceRetryHint(extraction: extraction, clock: clock)),
    ),
  );
  await tester.pump(); // the localization delegates load asynchronously
}

void main() {
  final hint = find.byKey(const ValueKey('voice-retry-hint'));

  testWidgets('shown while the voice token is valid', (tester) async {
    await _pump(tester, _extraction(token: _token), () => _expiry.subtract(const Duration(minutes: 5)));
    expect(hint, findsOneWidget);
    expect(find.text(AppLocalizations(const Locale('en')).voiceRetryHint), findsOneWidget);
  });

  testWidgets('hidden when no token was issued, or it does not look like one', (tester) async {
    await _pump(tester, _extraction(), () => _expiry.subtract(const Duration(minutes: 5)));
    expect(hint, findsNothing);
    await _pump(tester, _extraction(token: 'garbage'), () => _expiry.subtract(const Duration(minutes: 5)));
    expect(hint, findsNothing);
  });

  testWidgets('hidden when the token has already expired', (tester) async {
    await _pump(tester, _extraction(token: _token), () => _expiry.add(const Duration(seconds: 1)));
    expect(hint, findsNothing);
  });

  testWidgets('goes away by itself when the token expires while the screen stays open', (tester) async {
    var now = _expiry.subtract(const Duration(minutes: 15));
    await _pump(tester, _extraction(token: _token), () => now);
    expect(hint, findsOneWidget);

    // Part-way through the 15 minutes: still there.
    now = _expiry.subtract(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 14));
    expect(hint, findsOneWidget);

    // The token runs out: the timer rebuilds and the promise is withdrawn.
    now = _expiry.add(const Duration(seconds: 2));
    await tester.pump(const Duration(minutes: 1, seconds: 2));
    expect(hint, findsNothing);
  });

  testWidgets('no timer is left running after the widget is removed', (tester) async {
    await _pump(tester, _extraction(token: _token), () => _expiry.subtract(const Duration(minutes: 5)));
    await tester.pumpWidget(const SizedBox());
    // A pending timer would fail the test at teardown.
  });
}
