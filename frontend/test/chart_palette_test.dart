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
  test('categorical chart colours: same count in both modes, all different', () {
    expect(AppTheme.chartCategorical.length, AppTheme.chartCategoricalDark.length);
    expect(AppTheme.chartCategorical.length, greaterThanOrEqualTo(6));
    expect(AppTheme.chartCategorical.toSet(), hasLength(AppTheme.chartCategorical.length));
    expect(AppTheme.chartCategoricalDark.toSet(), hasLength(AppTheme.chartCategoricalDark.length));
    expect(AppTheme.chartCategorical.first, AppTheme.jade);
  });

  test('each colour stands out from its card (3:1 for graphics)', () {
    for (final c in AppTheme.chartCategorical) {
      expect(_contrast(c, AppTheme.card), greaterThanOrEqualTo(3), reason: '$c on light');
    }
    for (final c in AppTheme.chartCategoricalDark) {
      expect(_contrast(c, AppTheme.darkCard), greaterThanOrEqualTo(3), reason: '$c on dark');
    }
  });
}
