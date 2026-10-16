import 'package:web/web.dart' as web;

/// The browser's user agent string.
String currentUserAgent() => web.window.navigator.userAgent;

/// The number of simultaneous touch points the device supports. Used to tell an
/// iPad in desktop mode (reports a Mac user agent, but has a touch screen) from
/// a real Mac (reports 0).
int currentMaxTouchPoints() => web.window.navigator.maxTouchPoints;
