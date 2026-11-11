import 'dart:math' as math;

/// A bar chart's value axis: its top and the gap between gridlines/labels.
typedef ChartAxis = ({double maxY, double interval});

/// A round axis for bars up to [peak]: the interval is 1, 2, 2.5 or 5 times
/// a power of ten (about four of them), and the top is a whole number of
/// intervals with a little headroom above the peak. Labels at every interval
/// are then evenly spaced, so the top one never sits on top of the one below
/// (as "4.61K" over "4K" did with a top of peak × 1.2).
ChartAxis niceAxis(double peak, {int targetIntervals = 4}) {
  if (peak <= 0 || peak.isNaN) return (maxY: 100, interval: 25);
  final raw = peak / targetIntervals;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final interval = [1.0, 2.0, 2.5, 5.0, 10.0]
          .map((m) => m * magnitude)
          .firstWhere((step) => step >= raw);
  final maxY = (peak * 1.05 / interval).ceil() * interval;
  return (maxY: maxY, interval: interval);
}
