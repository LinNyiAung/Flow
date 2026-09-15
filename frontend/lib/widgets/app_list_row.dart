import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';

/// The standard row used across transactions, notifications, budgets and
/// settings lists: a 40dp tonal leading circle, title/subtitle, and a
/// trailing value or chevron. Divider is drawn by the surrounding
/// [Column]/[ListView] via the app's [DividerThemeData] (inset 70dp).
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconBg,
    this.iconColor,
    this.trailingText,
    this.trailingTextColor,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconBg;
  final Color? iconColor;
  final String? trailingText;
  final Color? trailingTextColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg ?? scheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: iconColor ?? scheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailingText != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  trailingText!,
                  style: AppTheme.money(15, weight: FontWeight.w700, color: trailingTextColor ?? scheme.onSurface),
                ),
              ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
