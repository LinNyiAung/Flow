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
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor ?? scheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: AppTheme.money(17, weight: FontWeight.w700, color: scheme.onSurface)),
        ],
      ),
    );
  }
}
