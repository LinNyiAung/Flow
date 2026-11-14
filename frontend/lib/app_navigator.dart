import 'package:flutter/widgets.dart';

/// The app's root navigator, for navigation that has no BuildContext of its
/// own: the "session expired" → login redirect, a tapped push, and a tapped
/// notice that first switches the Personal / Family book (the switch closes
/// every screen above Home, the one that was tapped included, so the target
/// is pushed here). Set on the `MaterialApp` in `main.dart`.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
