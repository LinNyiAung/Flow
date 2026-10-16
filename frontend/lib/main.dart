import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:frontend/platform/platform_info.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frontend/providers/app_version_provider.dart';
import 'package:frontend/providers/budget_provider.dart';
import 'package:frontend/providers/feedback_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/insight_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/screens/budgets/budgets_screen.dart';
import 'package:frontend/screens/charts/inflow_analytics_screen.dart';
import 'package:frontend/screens/charts/outflow_analytics_screen.dart';
import 'package:frontend/screens/goals/goals_screen.dart';
import 'package:frontend/screens/insights/insights_screen.dart';
import 'package:frontend/screens/notifications/notifications_screen.dart';
import 'package:frontend/screens/report/reports_screen.dart';
import 'package:frontend/screens/settings/currency_settings_screen.dart';
import 'package:frontend/screens/settings/feedback_screen.dart';
import 'package:frontend/screens/settings/language_settings_screen.dart';
import 'package:frontend/screens/settings/notification_settings_screen.dart';
import 'package:frontend/screens/settings/privacy_policy_screen.dart';
import 'package:frontend/screens/settings/settings_screen.dart';
import 'package:frontend/screens/settings/terms_and_conditions_screen.dart';
import 'package:frontend/screens/settings/theme_settings_screen.dart';
import 'package:frontend/screens/subscription/subscription_screen.dart';
import 'package:frontend/screens/transactions/transactions_list_screen.dart';
import 'package:frontend/screens/update/force_update_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/fcm_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/services/notification_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/web_phone_frame.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/transaction_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/ai/ai_chat_screen.dart';

/// Global navigator, used for app-wide navigation that has no BuildContext
/// (e.g. the "session expired" → login redirect).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Route that resets the whole stack to a fresh AuthWrapper (login or home).
Route<void> authWrapperRoute() => MaterialPageRoute<void>(
      builder: (_) => const AuthWrapper(),
      settings: const RouteSettings(name: '/'),
    );

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the saved locale before the first frame so Myanmar users don't see
  // an English flash.
  final languageCode = await LocalizationService.getSelectedLanguage();
  ApiService.currentLanguage = languageCode;

  // No Firebase / push / local notifications on the web.
  if (!PlatformInfo.isWeb) {
    await Firebase.initializeApp();
    await FCMService().initialize();
    await NotificationService().initialize();
  }

  runApp(MyApp(initialLocale: Locale(languageCode)));
}

class MyApp extends StatefulWidget {
  final Locale initialLocale;

  const MyApp({super.key, this.initialLocale = const Locale('en')});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Locale _locale = widget.initialLocale;

  // Per-user providers are owned here so that logout / session expiry /
  // switching accounts can wipe all of them in one place.
  final AuthProvider _authProvider = AuthProvider();
  final AppVersionProvider _appVersionProvider = AppVersionProvider();
  final TransactionProvider _transactionProvider = TransactionProvider();
  final ChatProvider _chatProvider = ChatProvider();
  final GoalProvider _goalProvider = GoalProvider();
  final InsightProvider _insightProvider = InsightProvider();
  final BudgetProvider _budgetProvider = BudgetProvider();
  final NotificationProvider _notificationProvider = NotificationProvider();
  final FeedbackProvider _feedbackProvider = FeedbackProvider();
  final ThemeProvider _themeProvider = ThemeProvider()..loadThemeMode();

  @override
  void initState() {
    super.initState();
    _authProvider.onSessionReset = _resetUserState;
    _authProvider.onLanguagePreference =
        (code) => _changeLanguage(Locale(code));
    ApiService.onSessionExpired = _handleSessionExpired;
  }

  void _resetUserState() {
    _transactionProvider.reset();
    _chatProvider.reset();
    _goalProvider.reset();
    _insightProvider.reset();
    _budgetProvider.reset();
    _notificationProvider.reset();
    _feedbackProvider.reset();
    _appVersionProvider.reset();
  }

  /// [token] is the token the rejected request used; a 401 for an older
  /// token than the stored one is ignored by [AuthProvider.handleSessionExpired].
  Future<void> _handleSessionExpired(String token) async {
    final wasSignedIn = await _authProvider.handleSessionExpired(token);
    if (wasSignedIn) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        authWrapperRoute(),
        (route) => false,
      );
    }
  }

  void _changeLanguage(Locale locale) {
    ApiService.currentLanguage = locale.languageCode;
    if (!mounted || locale == _locale) return;
    setState(() {
      _locale = locale;
    });
  }

  @override
  void dispose() {
    ApiService.onSessionExpired = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _appVersionProvider),
        ChangeNotifierProvider.value(value: _transactionProvider),
        ChangeNotifierProvider.value(value: _chatProvider),
        ChangeNotifierProvider.value(value: _goalProvider),
        ChangeNotifierProvider.value(value: _insightProvider),
        ChangeNotifierProvider.value(value: _budgetProvider),
        ChangeNotifierProvider.value(value: _notificationProvider),
        ChangeNotifierProvider.value(value: _feedbackProvider),
        ChangeNotifierProvider.value(value: _themeProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Toe Pwar',
          debugShowCheckedModeBanner: false,
          builder: (context, child) =>
              PlatformInfo.isWeb ? WebPhoneFrame(child: child!) : child!,
          locale: _locale,
          supportedLocales: const [Locale('en', ''), Locale('my', '')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeProvider.themeMode,
          initialRoute: '/',
          routes: {
            '/': (context) => const AuthWrapper(),
            '/ai-chat': (context) => AiChatScreen(),
            '/goals': (context) => GoalsScreen(),
            '/outflow-analytics': (context) => OutflowAnalyticsScreen(),
            '/inflow-analytics': (context) => InflowAnalyticsScreen(),
            '/insights': (context) => InsightsScreen(),
            '/reports': (context) => ReportsScreen(),
            '/budgets': (context) => BudgetsScreen(),
            '/transactions': (context) => TransactionsListScreen(),
            '/notifications': (context) => NotificationsScreen(),
            '/subscription': (context) => SubscriptionScreen(),
            '/settings': (context) => SettingsScreen(),
            '/notification-settings': (context) => NotificationSettingsScreen(),
            '/currency-settings': (context) => CurrencySettingsScreen(),
            '/theme-settings': (context) => ThemeSettingsScreen(),
            '/privacy-policy': (context) => PrivacyPolicyScreen(),
            '/terms-conditions': (context) => TermsAndConditionsScreen(),
            '/login': (context) => const LoginScreen(),
            '/feedback': (context) => FeedbackScreen(),
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/language-settings') {
              return MaterialPageRoute(
                settings: settings,
                builder: (context) =>
                    LanguageSettingsScreen(onLanguageChanged: _changeLanguage),
              );
            }
            return null;
          },
        ),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  /// User id the force-update check was run for (null = not started).
  String? _versionCheckedForUser;
  bool _versionCheckDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      // Restore a saved session on app start. Skipped when we got here
      // right after a successful login (already authenticated).
      if (!authProvider.isAuthenticated) {
        authProvider.checkAuthStatus();
      }
    });
  }

  Future<void> _checkVersion() async {
    // The web version is always current: no force-update check.
    if (PlatformInfo.isWeb) {
      if (mounted) setState(() => _versionCheckDone = true);
      return;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final platform =
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      if (!mounted) return;
      await Provider.of<AppVersionProvider>(
        context,
        listen: false,
      ).checkVersion(
        currentVersion: info.version, // e.g. "1.2.0"
        platform: platform,
      );
    } catch (e) {
      // If PackageInfo or version check fails, don't block the user
      debugPrint('Version check skipped: $e');
    } finally {
      if (mounted) setState(() => _versionCheckDone = true);
    }
  }

  Widget _spinner(BuildContext context) => Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, AppVersionProvider>(
      builder: (context, authProvider, versionProvider, child) {
        // ── Step 1: restore failed for a transient reason (timeout /
        // offline / 5xx): the token is kept, offer retry instead of login.
        // Stays up while a retry runs (it shows its own progress). ──
        if (!authProvider.isAuthenticated &&
            authProvider.sessionRestoreFailed) {
          return const _SessionRestoreRetryScreen();
        }

        // ── Step 1b: restoring a saved session (can take up to a minute on
        // a server cold start) ──
        final authChecking =
            authProvider.isAuthChecking && !authProvider.isAuthenticated;
        if (authChecking) return const _StartupSpinner();

        // ── Step 2: Not logged in → Login screen ──
        if (!authProvider.isAuthenticated) {
          _versionCheckedForUser = null;
          _versionCheckDone = false;
          return const LoginScreen(embedded: true);
        }

        // ── Step 3: force-update check, once per signed-in user (also right
        // after a fresh login — the endpoint requires auth). HomeScreen is
        // only built after it finishes, so it is never built twice. ──
        final userId = authProvider.user!.id;
        if (_versionCheckedForUser != userId) {
          _versionCheckedForUser = userId;
          _versionCheckDone = false;
          WidgetsBinding.instance.addPostFrameCallback((_) => _checkVersion());
        }
        if (!_versionCheckDone || versionProvider.isLoading) {
          return _spinner(context);
        }

        if (versionProvider.requiresForceUpdate) {
          return const ForceUpdateScreen();
        }

        // ── Step 4: All clear → home (fresh state per user) ──
        return HomeScreen(key: ValueKey('home-$userId'));
      },
    );
  }
}

/// Spinner shown while the saved session is restored. After a few seconds
/// it explains that the server may be waking up (Render cold start).
class _StartupSpinner extends StatefulWidget {
  const _StartupSpinner();

  @override
  State<_StartupSpinner> createState() => _StartupSpinnerState();
}

class _StartupSpinnerState extends State<_StartupSpinner> {
  Timer? _hintTimer;
  bool _showSlowHint = false;

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showSlowHint = true);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
              ),
              if (_showSlowHint) ...[
                const SizedBox(height: 20),
                Text(
                  AppLocalizations.of(context).connectingToServer,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when restoring the saved session failed for a transient reason.
/// The user stays signed in (token kept); retries automatically and offers
/// a manual retry or signing out.
class _SessionRestoreRetryScreen extends StatefulWidget {
  const _SessionRestoreRetryScreen();

  @override
  State<_SessionRestoreRetryScreen> createState() =>
      _SessionRestoreRetryScreenState();
}

class _SessionRestoreRetryScreenState extends State<_SessionRestoreRetryScreen>
    with WidgetsBindingObserver {
  static const Duration _autoRetryDelay = Duration(seconds: 10);
  Timer? _retryTimer;

  /// App in the background: no auto-retries (they would only burn battery
  /// and data); one retry runs as soon as the app is resumed.
  bool _backgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The screen stays mounted while retries run; re-armed after each failure.
    _scheduleRetry();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _backgrounded = true;
        _retryTimer?.cancel();
        _retryTimer = null;
      case AppLifecycleState.resumed:
        if (_backgrounded) {
          _backgrounded = false;
          _retry();
        }
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (_backgrounded) return;
    _retryTimer = Timer(_autoRetryDelay, _retry);
  }

  Future<void> _retry() async {
    if (!mounted || _backgrounded) return;
    _retryTimer?.cancel();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await auth.checkAuthStatus();
    // Still unreachable → try again later (this screen is still shown).
    if (mounted && auth.sessionRestoreFailed && !auth.isAuthenticated) {
      _scheduleRetry();
    }
  }

  void _logout() {
    _retryTimer?.cancel();
    // Clears isAuthChecking immediately and makes an in-flight retry's late
    // result be ignored, so the startup spinner never shows.
    Provider.of<AuthProvider>(context, listen: false).logout();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final auth = Provider.of<AuthProvider>(context);
    final details = auth.sessionRestoreError;
    final retrying = auth.isAuthChecking;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, size: 56, color: scheme.primary),
                const SizedBox(height: 20),
                Text(
                  localizations.sessionRestoreFailedTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  localizations.sessionRestoreFailedBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                if (details != null && details.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    details,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: retrying ? null : _retry,
                  icon: retrying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(localizations.tryAgain),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _logout,
                  child: Text(localizations.drawerLogout),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
