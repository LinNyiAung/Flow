import 'package:flutter/material.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/home/home_screen.dart';
import '../screens/transactions/transactions_list_screen.dart';

class AppDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea).withOpacity(0.05),
              Colors.white.withOpacity(0.9),
            ],
          ),
        ),
        child: Column(
          children: <Widget>[
            // Drawer Header
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
              ),
              child: Container(
                width: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white.withOpacity(0.8),
                      child: Text(
                        user?.name != null && user!.name.isNotEmpty
                            ? user.name[0].toUpperCase()
                            : 'U',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF667eea),
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      user?.name ?? 'Welcome',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      user?.email ?? '',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Navigation Items in Expanded ListView
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  ListTile(
                    leading: Icon(Icons.dashboard, color: Color(0xFF667eea)),
                    title: Text(
                      'Dashboard',
                      style: GoogleFonts.poppins(fontSize: 16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      if (ModalRoute.of(context)?.settings.name != '/') {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => HomeScreen()),
                        );
                      }
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Icon(Icons.list_alt, color: Color(0xFF764ba2)),
                    title: Text(
                      'Transactions',
                      style: GoogleFonts.poppins(fontSize: 16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TransactionsListScreen()),
                      );
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.flag, color: Colors.white, size: 20),
                    ),
                    title: Text(
                      'Goals',
                      style: GoogleFonts.poppins(fontSize: 16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/goals');
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.trending_up, color: Colors.white, size: 18),
                    ),
                    title: Text(
                      'Inflow Analytics',
                      style: GoogleFonts.poppins(fontSize: 16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/inflow-analytics');
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFF5722), Color(0xFFE64A19)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.analytics, color: Colors.white, size: 18),
                    ),
                    title: Text(
                      'Outflow Analytics',
                      style: GoogleFonts.poppins(fontSize: 16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/outflow-analytics');
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.assessment, color: Colors.white, size: 16),
                    ),
                    title: Text(
                      'Financial Reports',
                      style: GoogleFonts.poppins(fontSize: 16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/reports');
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFF9800), Color(0xFFF57C00)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.account_balance_wallet, color: Colors.white, size: 18),
                    ),
                    title: Text(
                      'Budgets',
                      style: GoogleFonts.poppins(fontSize: 16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/budgets');
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFB74D), Color(0xFFFF9800)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.lightbulb, color: Colors.white, size: 16),
                    ),
                    title: Text(
                      'AI Insights',
                      style: GoogleFonts.poppins(fontSize: 16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/insights');
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.smart_toy, color: Colors.white, size: 16),
                    ),
                    title: Text(
                      'AI Assistant',
                      style: GoogleFonts.poppins(fontSize: 16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/ai-chat');
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                ],
              ),
            ),
            
            // Logout button at bottom
            Container(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showLogoutDialog(context);
                  },
                  icon: Icon(Icons.logout, color: Colors.white),
                  label: Text(
                    'Logout',
                    style: GoogleFonts.poppins(
                      color: Colors.white, 
                      fontWeight: FontWeight.w500
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Logout',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          content: Text(
            'Are you sure you want to logout?',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(
                  color: Colors.grey[600],
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Provider.of<AuthProvider>(context, listen: false).logout();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => LoginScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Logout',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}