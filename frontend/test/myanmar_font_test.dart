import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

/// The bundled Noto Sans Myanmar is the fallback on every theme text style,
/// so Myanmar text never waits on a downloaded fallback font (web showed
/// empty boxes for seconds).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('the font files and licence are bundled', () async {
    for (final asset in [
      'assets/fonts/NotoSansMyanmar-Regular.ttf',
      'assets/fonts/NotoSansMyanmar-Bold.ttf',
    ]) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(100000), reason: asset);
    }
    final ofl = await rootBundle.loadString('assets/fonts/NotoSansMyanmar-OFL.txt');
    expect(ofl, contains('SIL Open Font License'));
  });

  test('every light and dark theme text style falls back to Noto Sans Myanmar', () async {
    // Building a theme starts Manrope loads, which can't succeed offline and
    // fail later; build both themes in one zone that swallows only those.
    final themes = <String, ThemeData>{};
    runZonedGuarded(() {
      themes['light'] = AppTheme.light;
      themes['dark'] = AppTheme.dark;
    }, (error, _) {
      if (!'$error'.contains('Manrope')) throw error;
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));

    for (final entry in themes.entries) {
      final theme = entry.value;
      final t = theme.textTheme;
      final styles = <String, TextStyle?>{
        'bodyMedium': t.bodyMedium,
        'bodySmall': t.bodySmall,
        'titleLarge': t.titleLarge,
        'labelSmall': t.labelSmall,
        'displaySmall (money)': t.displaySmall,
        'headlineSmall (untouched default)': t.headlineSmall,
        'primaryTextTheme.bodyMedium': theme.primaryTextTheme.bodyMedium,
        'filled button': theme.filledButtonTheme.style?.textStyle?.resolve({}),
        'elevated button': theme.elevatedButtonTheme.style?.textStyle?.resolve({}),
        'text button': theme.textButtonTheme.style?.textStyle?.resolve({}),
        'chip label': theme.chipTheme.labelStyle,
        'input hint': theme.inputDecorationTheme.hintStyle,
        'snackbar': theme.snackBarTheme.contentTextStyle,
        'appBar title': theme.appBarTheme.titleTextStyle,
      };
      for (final s in styles.entries) {
        final reason = '${entry.key} ${s.key}';
        expect(s.value, isNotNull, reason: reason);
        expect(s.value!.fontFamilyFallback, contains('NotoSansMyanmar'), reason: reason);
      }
    }
  });
}
