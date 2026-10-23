// The browser's user agent string and touch-point count (empty / 0 outside the
// browser). Used to hide the "Get the Android app" link on iPhone/iPad, which
// cannot install an APK.
export 'user_agent_io.dart' if (dart.library.js_interop) 'user_agent_web.dart';
