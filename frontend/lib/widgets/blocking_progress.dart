import 'package:flutter/material.dart';

/// Shows a modal spinner that the Android back button can't dismiss and
/// returns a callback that closes exactly that spinner.
///
/// Closing by route (instead of `Navigator.pop`) means a late or repeated
/// close can never pop the screen underneath, and the callback is safe to
/// call after the calling screen has been disposed.
VoidCallback showBlockingProgress(BuildContext context) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: Center(
        child: CircularProgressIndicator(color: Theme.of(dialogContext).colorScheme.primary),
      ),
    ),
  );
  navigator.push(route);
  return () {
    if (route.isActive) navigator.removeRoute(route);
  };
}
