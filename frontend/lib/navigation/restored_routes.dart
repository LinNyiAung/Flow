import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:provider/provider.dart';

/// The routes the app starts with (MaterialApp.onGenerateInitialRoutes): the
/// home route, and on a browser reload of another page (`#/notifications`)
/// that page on top of it.
///
/// A reloaded page is built only once the saved session is restored. Restoring
/// it resets every per-user store (AuthProvider.onSessionReset), so a page that
/// loaded its data before that would be left empty (a reload of the
/// notifications showed "No notifications yet"). Until then the page shows a
/// spinner; when nobody turns out to be signed in, or the session cannot be
/// restored, it steps aside so the home route shows the sign-in or the retry.
///
/// [pageFor] gives a page's builder by route name (null: not a page, so the
/// app starts on the home route alone). [public] pages (the policies) open at
/// once, signed in or not.
List<Route<dynamic>> restoredInitialRoutes(
  String initialRoute, {
  required WidgetBuilder? Function(String name) pageFor,
  Set<String> public = const {},
}) {
  final home = MaterialPageRoute<void>(
    settings: const RouteSettings(name: '/'),
    builder: pageFor('/')!,
  );
  final page = initialRoute == '/' ? null : pageFor(initialRoute);
  if (page == null) return [home];
  return [
    home,
    MaterialPageRoute<void>(
      settings: RouteSettings(name: initialRoute),
      builder: public.contains(initialRoute) ? page : (_) => AfterSessionRestored(builder: page),
    ),
  ];
}

/// Builds [builder] once a user is signed in (keyed by the user, so another
/// account gets a fresh page); see [restoredInitialRoutes].
class AfterSessionRestored extends StatefulWidget {
  final WidgetBuilder builder;

  const AfterSessionRestored({super.key, required this.builder});

  @override
  State<AfterSessionRestored> createState() => _AfterSessionRestoredState();
}

class _AfterSessionRestoredState extends State<AfterSessionRestored> {
  /// The session restore has been started (here or by the home route).
  bool _restoreStarted = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      // Usually already running (the home route starts it); a second call returns at once.
      if (!auth.isAuthenticated) auth.checkAuthStatus();
      setState(() => _restoreStarted = true);
    });
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) Navigator.of(context).removeRoute(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    if (auth.isAuthenticated && user != null) {
      return KeyedSubtree(key: ValueKey(user.id), child: Builder(builder: widget.builder));
    }
    if (_restoreStarted && !auth.isAuthChecking) _leave(); // signed out, or the restore failed
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}
