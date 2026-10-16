import 'package:flutter/foundation.dart';

/// The single switch for web-only behaviour. Code checks [isWeb] instead of
/// `kIsWeb` so tests can flip it (restore it in tearDown). A plain field, not
/// `@visibleForTesting`: production code reads it everywhere.
class PlatformInfo {
  PlatformInfo._();

  static bool isWeb = kIsWeb;
}
