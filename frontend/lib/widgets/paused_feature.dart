import 'package:flutter/material.dart';
import 'package:frontend/providers/app_control_provider.dart';

/// When the owner has paused [key] (see [AppControlProvider]), shows the
/// server's message in a SnackBar and returns true: the caller then does
/// nothing. Returns false when the feature is open, or when there is no
/// provider above [context] (nothing is paused then).
bool showIfPaused(BuildContext context, String key) {
  final control = AppControlProvider.maybeOf(context, listen: false);
  if (control == null || !control.isPaused(key)) return false;
  final message = control.pausedMessage(key);
  if (message != null && message.isNotEmpty) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
  return true;
}

/// [child] greyed to 40% while [featureKey] is paused. It stays tappable, so
/// the tap can show the message (see [showIfPaused]).
class PausedLook extends StatelessWidget {
  final String featureKey;
  final Widget child;

  const PausedLook({super.key, required this.featureKey, required this.child});

  @override
  Widget build(BuildContext context) {
    final paused =
        AppControlProvider.maybeOf(context)?.isPaused(featureKey) ?? false;
    return Opacity(opacity: paused ? 0.4 : 1.0, child: child);
  }
}
