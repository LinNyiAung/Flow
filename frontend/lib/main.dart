import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
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
import 'package:frontend/screens/subscription/subscription_screen.dart';
import 'package:frontend/screens/update/force_update_screen.dart';
import 'package:frontend/services/fcm_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/services/notification_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/transaction_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/ai/ai_chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  await FCMService().initialize();
  await NotificationService().initialize();

  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale _locale = const Locale('en');

  @override
  void initState() {
    super.initState();
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final languageCode = await LocalizationService.getSelectedLanguage();
    setState(() {
      _locale = Locale(languageCode);
    });
  }

  void _changeLanguage(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AppVersionProvider()), // NEW
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => GoalProvider()),
        ChangeNotifierProvider(create: (_) => InsightProvider()),
        ChangeNotifierProvider(create: (_) => BudgetProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => FeedbackProvider()),
      ],
      child: MaterialApp(
        title: 'Toe Pwar',
        debugShowCheckedModeBanner: false,
        locale: _locale,
        supportedLocales: const [Locale('en', ''), Locale('my', '')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: false,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(
              vertical: 15.0,
              horizontal: 15.0,
            ),
          ),
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => AuthWrapper(),
          '/ai-chat': (context) => AiChatScreen(),
          '/goals': (context) => GoalsScreen(),
          '/outflow-analytics': (context) => OutflowAnalyticsScreen(),
          '/inflow-analytics': (context) => InflowAnalyticsScreen(),
          '/insights': (context) => InsightsScreen(),
          '/reports': (context) => ReportsScreen(),
          '/budgets': (context) => BudgetsScreen(),
          '/notifications': (context) => NotificationsScreen(),
          '/subscription': (context) => SubscriptionScreen(),
          '/settings': (context) => SettingsScreen(),
          '/notification-settings': (context) => NotificationSettingsScreen(),
          '/currency-settings': (context) => CurrencySettingsScreen(),
          '/privacy-policy': (context) => PrivacyPolicyScreen(),
          '/terms-conditions': (context) => TermsAndConditionsScreen(),
          '/login': (context) => LoginScreen(),
          '/feedback': (context) => FeedbackScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/language-settings') {
            return MaterialPageRoute(
              builder: (context) =>
                  LanguageSettingsScreen(onLanguageChanged: _changeLanguage),
            );
          }
          return null;
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 1. Check auth first
      await Provider.of<AuthProvider>(context, listen: false).checkAuthStatus();

      // 2. Then check version (only if logged in — endpoint requires auth)
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated) {
        await _checkVersion();
      }
    });
  }

  Future<void> _checkVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final platform = Platform.isIOS ? 'ios' : 'android';

      await Provider.of<AppVersionProvider>(
        context,
        listen: false,
      ).checkVersion(
        currentVersion: info.version, // e.g. "1.2.0"
        platform: platform,
      );
    } catch (e) {
      // If PackageInfo or version check fails, don't block the user
      print('⚠️ Version check skipped: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, AppVersionProvider>(
      builder: (context, authProvider, versionProvider, child) {
        // ── Step 1: Show spinner while auth or version check is in progress ──
        if (authProvider.isAuthChecking || versionProvider.isLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
              ),
            ),
          );
        }

        // ── Step 2: Not logged in → Login screen ──
        if (!authProvider.isAuthenticated) {
          return LoginScreen();
        }

        // ── Step 3: Force update required → block with update screen ──
        if (versionProvider.requiresForceUpdate) {
          return const ForceUpdateScreen();
        }

        // ── Step 4: All clear → show home ──
        return HomeScreen();
      },
    );
  }
}
