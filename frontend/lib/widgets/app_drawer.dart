import 'package:flutter/material.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/home/home_screen.dart';
import '../screens/transactions/transactions_list_screen.dart';
import '../widgets/premium_badge.dart';  // NEW
import 'package:frontend/services/responsive_helper.dart';

class AppDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final localizations = AppLocalizations.of(context);
    final responsive = ResponsiveHelper(context);

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
                    Row(
                      children: [
                        CircleAvatar(
                          radius: responsive.iconSize(mobile: 30),
                          backgroundColor: Colors.white.withOpacity(0.8),
                          child: Text(
                            user?.name != null && user!.name.isNotEmpty
                                ? user.name[0].toUpperCase()
                                : 'U',
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF667eea),
                            ),
                          ),
                        ),
                        // NEW: Show premium badge if user is premium
                        if (authProvider.isPremium) ...[
                          SizedBox(width: 8),
                          PremiumBadge(small: true),
                        ],
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      user?.name ?? localizations.takeUploadPhoto,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      user?.email ?? '',
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                    // NEW: Show expiry date if premium
                    if (authProvider.isPremium && authProvider.subscriptionExpiresAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${localizations.expiresOn}: ${_formatDate(authProvider.subscriptionExpiresAt!)}',
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs10,
                            color: Colors.white.withOpacity(0.7),
                          ),
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
                      localizations.dashboard,
                      style: GoogleFonts.poppins(fontSize: responsive.fs16),
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
                      localizations.transactions,
                      style: GoogleFonts.poppins(fontSize: responsive.fs16),
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
                      width: responsive.icon24,
                      height: responsive.icon24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.flag, color: Colors.white, size: responsive.icon20),
                    ),
                    title: Text(
                      localizations.goals,
                      style: GoogleFonts.poppins(fontSize: responsive.fs16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/goals');
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      width: responsive.icon24,
                      height: responsive.icon24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFF9800), Color(0xFFF57C00)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.account_balance_wallet, color: Colors.white, size: responsive.icon20),
                    ),
                    title: Text(
                      localizations.budgets,
                      style: GoogleFonts.poppins(fontSize: responsive.fs16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/budgets');
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      width: responsive.icon24,
                      height: responsive.icon24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.trending_up, color: Colors.white, size: responsive.icon20),
                    ),
                    title: Text(
                      localizations.inflowAnalytics,
                      style: GoogleFonts.poppins(fontSize: responsive.fs16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/inflow-analytics');
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      width: responsive.icon24,
                      height: responsive.icon24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFF5722), Color(0xFFE64A19)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.analytics, color: Colors.white, size: responsive.icon20),
                    ),
                    title: Text(
                      localizations.outflowAnalytics,
                      style: GoogleFonts.poppins(fontSize: responsive.fs16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/outflow-analytics');
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      width: responsive.icon24,
                      height: responsive.icon24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.assessment, color: Colors.white, size: responsive.icon20),
                    ),
                    title: Text(
                      localizations.financialReports,
                      style: GoogleFonts.poppins(fontSize: responsive.fs16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/reports');
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      width: responsive.icon24,
                      height: responsive.icon24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFB74D), Color(0xFFFF9800)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.lightbulb, color: Colors.white, size: responsive.icon20),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            localizations.aiInsights,
                            style: GoogleFonts.poppins(fontSize: responsive.fs16),
                            
                          ),
                        ),
                        if (!authProvider.isPremium) ...[
                          SizedBox(width: 8),
                          Icon(Icons.lock, size: responsive.icon20, color: Color(0xFFFFD700)),
                        ],
                      ],
                    ),
                        trailing: !authProvider.isPremium 
                        ? Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Color(0xFFFFD700).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Color(0xFFFFD700), width: 1),
                            ),
                            child: Text(
                              localizations.premium,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFFD700),
                              ),
                            ),
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/insights');
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      width: responsive.icon24,
                      height: responsive.icon24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.smart_toy, color: Colors.white, size: responsive.icon20),
                    ),
                    title: Row(
                      children: [
                        Text(
                          localizations.aiAssistant,
                          style: GoogleFonts.poppins(fontSize: responsive.fs16),
                        ),
                        
                        if (!authProvider.isPremium) ...[
                          SizedBox(width: 8),
                          Icon(Icons.lock, size: responsive.icon20, color: Color(0xFFFFD700)),
                        ]
                      ],
                    ),
                        trailing: !authProvider.isPremium 
                        ? Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Color(0xFFFFD700).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Color(0xFFFFD700), width: 1),
                            ),
                            child: Text(
                              localizations.premium,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFFD700),
                              ),
                            ),
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/ai-chat');
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ListTile(
                    leading: Container(
                      width: responsive.icon24,
                      height: responsive.icon24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF607D8B), Color(0xFF455A64)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.settings, color: Colors.white, size: responsive.icon20),
                    ),
                    title: Text(
                      localizations.settings,
                      style: GoogleFonts.poppins(fontSize: responsive.fs16),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/settings');
                    },
                  ),
                  
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  // NEW: Subscription/Upgrade option
                  // ListTile(
                  //   leading: Container(
                  //     width: responsive.icon24,
                  //     height: responsive.icon24,
                  //     decoration: BoxDecoration(
                  //       gradient: LinearGradient(
                  //         colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  //       ),
                  //       borderRadius: BorderRadius.circular(4),
                  //     ),
                  //     child: Icon(Icons.star, color: Colors.white, size: responsive.icon20),
                  //   ),
                  //   title: Text(
                  //     authProvider.isPremium ? 'Manage Subscription' : 'Upgrade to Premium',
                  //     style: GoogleFonts.poppins(fontSize: responsive.fs16),
                  //   ),
                  //   onTap: () {
                  //     Navigator.pop(context);
                  //     Navigator.pushNamed(context, '/subscription');
                  //   },
                  // ),
                  // Divider(height: 1, thickness: 1, color: Colors.grey[200]),
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
                    localizations.drawerLogout,
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
                    padding: responsive.padding(vertical: 12, horizontal: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showLogoutDialog(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            localizations.drawerLogout,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          content: Text(
            localizations.dialogLogoutConfirm,
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