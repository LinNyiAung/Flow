import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/date_parsing.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

void main() {
  group('date parsing', () {
    test('wall-clock dates keep their fields and become local', () {
      final d = parseWallClock('2026-10-09T07:24:29.178000+00:00');
      expect(d.isUtc, isFalse);
      expect([d.year, d.month, d.day, d.hour, d.minute, d.second],
          [2026, 10, 9, 7, 24, 29]);
    });

    test('instants are converted to local time', () {
      final d = parseInstant('2026-10-09T07:24:29+00:00');
      expect(d.isUtc, isFalse);
      expect(d.toUtc(), DateTime.utc(2026, 10, 9, 7, 24, 29));
      // Legacy naive values are treated as UTC.
      expect(parseInstant('2026-10-09T07:24:29').toUtc(),
          DateTime.utc(2026, 10, 9, 7, 24, 29));
    });
  });

  group('error messages', () {
    test('422 detail list is joined', () {
      final r = http.Response(
        '{"detail":[{"loc":["body","password"],"msg":"String should have at least 6 characters"}]}',
        422,
      );
      expect(ApiService.errorMessage(r, 'fallback'),
          'password: String should have at least 6 characters');
    });

    test('400 string detail is returned as-is', () {
      final r = http.Response('{"detail":"Invalid category"}', 400);
      expect(ApiService.errorMessage(r, 'fallback'), 'Invalid category');
    });

    test('non-JSON body falls back without throwing', () {
      final r = http.Response('<html>Bad gateway</html>', 502);
      expect(ApiService.errorMessage(r, 'Failed'), 'Failed (502)');
    });
  });

  testWidgets('login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(
          localizationsDelegates: [AppLocalizations.delegate],
          supportedLocales: [Locale('en'), Locale('my')],
          home: LoginScreen(embedded: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TextFormField), findsNWidgets(2));
  });
}
