import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/settings/theme_settings_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Theme settings: the dividers stop short of the card edge', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en'), Locale('my')],
        home: ThemeSettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    final dividers = tester.widgetList<Divider>(find.byType(Divider)).toList();
    expect(dividers, hasLength(2));
    for (final d in dividers) {
      expect(d.endIndent, greaterThanOrEqualTo(16));
    }
  });
}
