import 'package:flutter/material.dart';

/// On wide (desktop) screens, shows the app in a centred phone-width column so
/// it looks exactly like it does on a phone. On narrow screens it does nothing.
///
/// Used as `MaterialApp.builder`, so it wraps the Navigator: routes, dialogs and
/// bottom sheets all live inside the column.
class WebPhoneFrame extends StatelessWidget {
  const WebPhoneFrame({super.key, required this.child});

  final Widget child;

  static const double frameWidth = 440;
  static const double breakpoint = 520;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Wider than the breakpoint -> phone column; at the breakpoint or narrower
    // -> full width.
    if (size.width <= breakpoint) return child;
    final mq = MediaQuery.of(context);

    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: SizedBox(
          width: frameWidth,
          child: MediaQuery(
            data: mq.copyWith(size: Size(frameWidth, mq.size.height)),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}
