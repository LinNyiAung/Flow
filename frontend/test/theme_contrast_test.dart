import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/theme/app_theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // The schemes, not AppTheme.light/dark: those load Google Fonts.
  for (final entry in {'light': AppTheme.lightScheme, 'dark': AppTheme.darkScheme}.entries) {
    final scheme = entry.value;
    group('${entry.key} scheme pairs', () {
      test('onSecondaryContainer on secondaryContainer is readable text', () {
        expect(_contrast(scheme.onSecondaryContainer, scheme.secondaryContainer), greaterThanOrEqualTo(4.5));
      });
      test('onPrimaryContainer on primaryContainer is readable text', () {
        expect(_contrast(scheme.onPrimaryContainer, scheme.primaryContainer), greaterThanOrEqualTo(4.5));
      });
      test('onTertiary on tertiary is readable text', () {
        expect(_contrast(scheme.onTertiary, scheme.tertiary), greaterThanOrEqualTo(4.5));
      });
    });
  }

  testWidgets('accentFor is readable on the surface and the outline-variant box in both modes', (tester) async {
    for (final scheme in [AppTheme.lightScheme, AppTheme.darkScheme]) {
      late Color accent;
      await tester.pumpWidget(Theme(
        data: ThemeData(colorScheme: scheme),
        child: Builder(builder: (context) {
          accent = AppTheme.accentFor(context);
          return const SizedBox();
        }),
      ));
      expect(_contrast(accent, scheme.surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(accent, scheme.outlineVariant), greaterThanOrEqualTo(4.5));
    }
  });
}
