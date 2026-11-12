import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:frontend/services/localization_service.dart';

/// Ko Toe Pwar (ကိုတိုးပွား), the app's mascot: a baby elephant in Myanmar
/// dress. Only these poses ship with the app (assets/mascot/); none of them
/// has text in it, so no extra fonts are needed.
enum MascotPose {
  /// Round head-and-shoulders avatar on a mint circle: the chat's face.
  face('face'),
  aibuddyHappy('aibuddy_happy'),
  quickaddJoy('quickadd_joy'),
  budgetpieHappy('budgetpie_happy'),
  goalJoy('goal_joy'),
  mailHappy('mail_happy'),
  ideaHappy('idea_happy'),
  offlineSad('offline_sad'),
  oopsSad('oops_sad'),
  upgradeJoy('upgrade_joy'),
  trophyJoy('trophy_joy');

  const MascotPose(this.fileName);

  final String fileName;

  String get asset => 'assets/mascot/$fileName.svg';

  /// Full-body poses are drawn on a 400 × 500 canvas; the face is round.
  double get aspectRatio => this == face ? 1 : 400 / 500;

  /// The pose for a full-page error: [offlineSad] when [message] says the
  /// server couldn't be reached (no connection, timeout), [oopsSad] for
  /// anything else.
  static MascotPose forError(String? message) =>
      isConnectionErrorMessage(message) ? offlineSad : oopsSad;
}

/// True when [message] is one of the app's "can't reach the server" errors
/// (see ApiService.networkErrorMessage / timeoutMessage, in either language)
/// or a raw socket / browser fetch failure.
bool isConnectionErrorMessage(String? message) {
  if (message == null || message.trim().isEmpty) return false;
  for (final lang in const ['en', 'my']) {
    final l = AppLocalizations(Locale(lang));
    if (message.contains(l.errorNetworkUnreachable) || message.contains(l.errorRequestTimedOut)) {
      return true;
    }
  }
  return RegExp(
    r'SocketException|Failed host lookup|XMLHttpRequest error|Connection (refused|reset|closed)|Network is unreachable',
    caseSensitive: false,
  ).hasMatch(message);
}

/// Ko Toe Pwar in one of his [MascotPose]s. [size] is his height (the face's
/// diameter); the width follows the pose.
///
/// Decorative by default (screen readers skip him): pass [semanticLabel] only
/// where he stands for something, such as the chat's top bar.
class Mascot extends StatelessWidget {
  const Mascot(this.pose, {super.key, this.size = 120, this.semanticLabel});

  /// His round face, e.g. next to a chat reply.
  const Mascot.face({super.key, this.size = 28, this.semanticLabel}) : pose = MascotPose.face;

  final MascotPose pose;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final width = size * pose.aspectRatio;
    // The box is the same before and after the SVG loads: nothing jumps.
    return SizedBox(
      width: width,
      height: size,
      child: SvgPicture.asset(
        pose.asset,
        width: width,
        height: size,
        fit: BoxFit.contain,
        excludeFromSemantics: semanticLabel == null,
        semanticsLabel: semanticLabel,
      ),
    );
  }
}
