import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/chart_scale.dart';

void main() {
  group('niceAxis', () {
    test('Income by Month: 4.61K peak gets a round top, not "4.61K" over "4K"', () {
      final axis = niceAxis(4610);
      expect(axis.maxY, 6000);
      expect(axis.interval, 2000);
    });

    test('Spending by Month: 1.94K peak', () {
      final axis = niceAxis(1940);
      expect(axis.maxY, 2500);
      expect(axis.interval, 500);
    });

    test('the top is always a whole number of intervals above the peak', () {
      for (final peak in <double>[0.4, 7, 13, 99, 100, 101, 936000, 1100000, 12345.67]) {
        final axis = niceAxis(peak);
        expect(axis.maxY, greaterThan(peak), reason: '$peak');
        final steps = axis.maxY / axis.interval;
        expect(steps, closeTo(steps.roundToDouble(), 1e-9), reason: '$peak');
        expect(steps, inInclusiveRange(2, 6), reason: '$peak');
      }
    });

    test('no data or no spending still gives a usable axis', () {
      expect(niceAxis(0).maxY, 100);
      expect(niceAxis(-5).maxY, 100);
      expect(niceAxis(0).interval, 25);
    });
  });
}
