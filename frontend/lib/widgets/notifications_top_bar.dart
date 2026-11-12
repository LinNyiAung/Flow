import 'package:flutter/material.dart';
import 'package:frontend/widgets/app_bar_title.dart';

/// Notifications' top bar: the title, and "Mark all read" while anything is
/// unread.
///
/// The button keeps its label when the title and the labelled button both fit
/// on one bar. Otherwise (Myanmar on a 360 px phone, where the label alone is
/// wider than half the bar) it becomes an icon-only button with the label as
/// its tooltip, so the title isn't squeezed down to "…".
class NotificationsTopBar extends StatelessWidget implements PreferredSizeWidget {
  const NotificationsTopBar({
    super.key,
    required this.title,
    required this.markAllReadLabel,
    required this.showMarkAllRead,
    required this.onMarkAllRead,
  });

  final String title;
  final String markAllReadLabel;
  final bool showMarkAllRead;
  final VoidCallback onMarkAllRead;

  static const _labelStyle = TextStyle(fontSize: 12);
  static const _iconSize = 18.0;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  /// Whether the title (one line) and the labelled button fit side by side.
  bool _labelFits(BuildContext context) {
    final theme = Theme.of(context);
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double widthOf(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    final titleStyle = theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge;
    final labelStyle = (theme.textButtonTheme.style?.textStyle?.resolve({}) ?? const TextStyle()).merge(_labelStyle);
    // Leading (back button), the bar's spacing around the title, the button's
    // padding, icon and gap, and the bar's right padding.
    const chrome = kToolbarHeight + NavigationToolbar.kMiddleSpacing * 2 + 28 + _iconSize + 8 + 8;
    final needed = widthOf(title, titleStyle) + widthOf(markAllReadLabel, labelStyle) + chrome;
    return needed <= MediaQuery.sizeOf(context).width;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final buttonStyle = TextButton.styleFrom(
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    );
    Widget? action;
    if (showMarkAllRead) {
      action = _labelFits(context)
          ? TextButton.icon(
              key: const Key('mark-all-read'),
              onPressed: onMarkAllRead,
              icon: const Icon(Icons.done_all_rounded, size: _iconSize),
              label: Text(markAllReadLabel, style: _labelStyle),
              style: buttonStyle,
            )
          : IconButton.filledTonal(
              key: const Key('mark-all-read'),
              tooltip: markAllReadLabel,
              onPressed: onMarkAllRead,
              icon: const Icon(Icons.done_all_rounded, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: scheme.secondaryContainer,
                foregroundColor: scheme.onSecondaryContainer,
              ),
            );
    }
    return AppBar(
      title: AppBarTitle(title),
      actions: [
        if (action != null) Padding(padding: const EdgeInsets.only(right: 8), child: action),
      ],
    );
  }
}
