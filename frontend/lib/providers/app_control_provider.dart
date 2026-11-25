import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:frontend/models/app_config.dart';
import 'package:frontend/services/api_service.dart';
import 'package:provider/provider.dart';

/// What the owner has switched in the admin panel (`GET /api/app/config`):
/// maintenance, paused features and the announcement.
///
/// Read when the app starts, every time it comes back to the front, when the
/// signed-in person changes (a tester gets in, see [AppConfig.canEnter]) and
/// when any call is refused as paused or under maintenance
/// ([ApiService.onAppControlSignal]). A failed read keeps the last config
/// (at first [AppConfig.open]: nothing paused), so a broken setting or a flaky
/// network never blocks the app.
class AppControlProvider extends ChangeNotifier with WidgetsBindingObserver {
  /// Where the config comes from; [ApiService.getAppConfig] in the app.
  final Future<AppConfig> Function() _fetch;

  AppConfig _config = AppConfig.open;
  bool _loading = false;
  bool _again = false;
  Future<void>? _running;
  bool _disposed = false;

  AppControlProvider({Future<AppConfig> Function()? fetcher})
      : _fetch = fetcher ??
            (() => ApiService.getAppConfig(lang: ApiService.currentLanguage)) {
    WidgetsBinding.instance.addObserver(this);
    // A dead server must not hold the app at the start-up spinner: after
    // [startTimeout] carry on with "nothing paused" (a late read still applies).
    _startTimer = Timer(startTimeout, _markInitialized);
    unawaited(refresh());
  }

  /// How long the start-up waits for the first read.
  static const Duration startTimeout = Duration(seconds: 10);

  Timer? _startTimer;
  bool _initialized = false;

  /// The first read has finished (or [startTimeout] passed): the app may now
  /// decide between the maintenance screen and login.
  bool get initialized => _initialized;

  void _markInitialized() {
    _startTimer?.cancel();
    _startTimer = null;
    if (_initialized) return;
    _initialized = true;
    notifyListeners();
  }

  /// The provider above [context], or null when there is none (a screen shown
  /// on its own, as in tests): the app then behaves as if nothing is paused.
  static AppControlProvider? maybeOf(BuildContext context, {bool listen = true}) {
    try {
      return Provider.of<AppControlProvider>(context, listen: listen);
    } on ProviderNotFoundException {
      return null;
    }
  }

  AppConfig get config => _config;

  /// True while a read is running.
  bool get isLoading => _loading;

  bool isPaused(String key) => _config.paused.containsKey(key);

  /// The message to show for a paused switch, or null when it is not paused.
  String? pausedMessage(String key) => _config.paused[key];

  /// Maintenance is on and this person may not get in.
  bool get blocked => _config.maintenanceOn && !_config.canEnter;

  /// Reads the config again. Never throws; a failure keeps the last config.
  /// A call made while one is running runs once more after it.
  /// The returned future completes when the last of those reads is done.
  Future<void> refresh() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _run();
  }

  Future<void> _run() async {
    _loading = true;
    notifyListeners();
    try {
      do {
        _again = false;
        try {
          final result = await _fetch();
          if (_disposed) return;
          _config = result;
        } catch (e) {
          debugPrint('AppControlProvider: refresh failed: $e');
        }
      } while (_again && !_disposed);
    } finally {
      _running = null;
      _loading = false;
      _markInitialized();
      notifyListeners();
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    _startTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
