// Saves a downloaded report PDF. The dart:io implementation is never compiled
// into the web build, and the package:web one never into the Android build.
export 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart';
