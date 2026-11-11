import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';

/// Linear progress bar used on budget/goal cards. Height 6dp on cards, 8dp
/// inside hero tonal containers; radius is always half the height. The fill
/// clamps at 100% and turns error-coloured past it — callers pass the raw
/// (possibly >1.0) [value] and read the overage from their own label.
class ProgressMeter extends StatelessWidget {
  const ProgressMeter({
    super.key,
    required this.value,
    this.height = 6,
    this.onHero = false,
    this.overrideColor,
  });

  final double value;
  final double height;
  final bool onHero;
  final Color? overrideColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clamped = value.clamp(0.0, 1.0);
    final over = value > 1.0;
    // On a hero (primaryContainer) the track is a faint tint of it and the
    // fill the accent: dark's `primary` is almost the hero's own green, so a
    // primary fill on a 25% track was barely visible (about 1:1). Off the
    // hero too: dark primary on the outlineVariant track was about 2.2:1.
    final track = onHero
        ? scheme.onPrimaryContainer.withValues(alpha: 0.12)
        : scheme.outlineVariant;
    final fill = overrideColor ??
        (over ? scheme.error : AppTheme.accentFor(context));
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: clamped,
        minHeight: height,
        backgroundColor: track,
        valueColor: AlwaysStoppedAnimation<Color>(fill),
      ),
    );
  }
}
