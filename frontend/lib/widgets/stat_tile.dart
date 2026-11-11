import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';

/// A small stat box nested inside a [HeroCard] — e.g. Inflow / Outflow.
/// Uses the app's surface colour so it reads as a lighter well inside the
/// tonal hero, per the handoff's "nested stat tiles use surface at radius 16".
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.stacked = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  /// Icon above the label instead of beside it, so the label gets the whole
  /// tile width. For rows of three tiles, which are narrow on a 360 px phone
  /// (Myanmar labels would otherwise be cut off).
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant);
    final iconWidget = Icon(icon, size: 18, color: iconColor ?? scheme.primary);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: stacked ? 10 : 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stacked) ...[
            iconWidget,
            const SizedBox(height: 4),
            // Wraps as needed; never cut off.
            Text(label, style: labelStyle),
          ] else
            Row(
              children: [
                iconWidget,
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: labelStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 6),
          // Scales down rather than overflow when a big amount meets a narrow tile.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, maxLines: 1, style: AppTheme.money(17, weight: FontWeight.w700, color: scheme.onSurface)),
          ),
        ],
      ),
    );
  }
}
