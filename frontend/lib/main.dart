import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/transaction_provider.dart';
import 'providers/chat_provider.dart'; // Add this import
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/ai/ai_chat_screen.dart'; // Add this import

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Provide AuthProvider to manage authentication state
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        // Provide TransactionProvider to manage transaction data
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        // Provide ChatProvider to manage AI chat functionality
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: MaterialApp(
        title: 'Flow Finance',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: AppBarTheme(
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
            contentPadding: EdgeInsets.symmetric(vertical: 15.0, horizontal: 15.0),
          ),
        ),
        // FIXED: Remove the conflicting routes and use initialRoute instead
        initialRoute: '/',
        routes: {
          '/': (context) => AuthWrapper(),
          '/ai-chat': (context) => AiChatScreen(),
          
        },
        // REMOVED: Don't use home property when routes contains '/'
        // home: AuthWrapper(),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AuthProvider>(context, listen: false).checkAuthStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (authProvider.isLoading) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        } else if (authProvider.isAuthenticated) {
          return HomeScreen();
        } else {
          return LoginScreen();
        }
      },
    );
  }
}