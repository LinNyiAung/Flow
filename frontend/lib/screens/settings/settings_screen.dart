import 'package:flutter/material.dart';
import 'package:frontend/screens/settings/change_password_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../providers/notification_provider.dart';
import 'edit_profile_screen.dart';
import 'package:frontend/services/responsive_helper.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final responsive = ResponsiveHelper(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.poppins(
            fontSize: responsive.fs20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.menu, color: Color(0xFF333333)),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          Padding(
            padding: responsive.padding(right: 16),
            child: Consumer<NotificationProvider>(
              builder: (context, notificationProvider, child) {
                return Stack(
                  children: [
                    Container(
                      padding: responsive.padding(all: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 1,
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.notifications_outlined,
                          color: Color(0xFF667eea),
                        ),
                        onPressed: () {
                          Navigator.pushNamed(context, '/notifications').then((_) {
                            notificationProvider.fetchUnreadCount();
                          });
                        },
                      ),
                    ),
                    if (notificationProvider.unreadCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: responsive.padding(all: 4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          child: Text(
                            '${notificationProvider.unreadCount > 9 ? '9+' : notificationProvider.unreadCount}',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: responsive.fs10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF667eea).withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: ListView(
          padding: responsive.padding(all: 20),
          children: [
            // Profile Card
            Container(
              padding: responsive.padding(all: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF667eea).withOpacity(0.3),
                    spreadRadius: 2,
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Profile Avatar
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white,
                        child: Text(
                          user?.name != null && user!.name.isNotEmpty
                              ? user.name[0].toUpperCase()
                              : 'U',
                          style: GoogleFonts.poppins(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF667eea),
                          ),
                        ),
                      ),
                      if (authProvider.isPremium)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Color(0xFFFFD700),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Icon(
                              Icons.star,
                              color: Colors.white,
                              size: responsive.icon16,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: responsive.sp16),
                  // Name
                  Text(
                    user?.name ?? 'User',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: responsive.sp4),
                  // Email
                  Text(
                    user?.email ?? '',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs14,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  SizedBox(height: responsive.sp12),
                  // Subscription Badge
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: authProvider.isPremium
                          ? Color(0xFFFFD700).withOpacity(0.3)
                          : Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
                      border: Border.all(
                        color: authProvider.isPremium
                            ? Color(0xFFFFD700)
                            : Colors.white.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          authProvider.isPremium ? Icons.star : Icons.lock_outline,
                          color: Colors.white,
                          size: responsive.icon16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          authProvider.isPremium ? 'Premium Member' : 'Free Plan',
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (authProvider.isPremium && authProvider.subscriptionExpiresAt != null) ...[
                    SizedBox(height: responsive.sp8),
                    Text(
                      'Expires: ${_formatDate(authProvider.subscriptionExpiresAt!)}',
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs11,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            SizedBox(height: responsive.sp24),

            // Account Settings Section
            _buildSectionHeader('Account'),
            SizedBox(height: responsive.sp12),

            _buildSettingCard(
              icon: Icons.person_outline,
              title: 'Edit Profile',
              subtitle: 'Update your name',
              gradientColors: [Color(0xFF667eea), Color(0xFF764ba2)],
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => EditProfileScreen()),
                );
                if (result == true) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Profile updated successfully!',
                        style: GoogleFonts.poppins(color: Colors.white),
                      ),
                      backgroundColor: Color(0xFF4CAF50),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),

            SizedBox(height: responsive.sp8),

            _buildSettingCard(
              icon: Icons.lock_outline,
              title: 'Change Password',
              subtitle: 'Update your password',
              gradientColors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ChangePasswordScreen()),
                );
                if (result == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Password changed successfully!',
                        style: GoogleFonts.poppins(color: Colors.white),
                      ),
                      backgroundColor: Color(0xFF4CAF50),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(8))),
                    ),
                  );
                }
              },
            ),


            SizedBox(height: responsive.sp8),

            _buildSettingCard(
              icon: Icons.language,
              title: 'Language',
              subtitle: 'Change app language',
              gradientColors: [Color(0xFF00BCD4), Color(0xFF0097A7)],
              onTap: () {
                Navigator.pushNamed(context, '/language-settings');
              },
            ),


            SizedBox(height: responsive.sp8),

            _buildSettingCard(
              icon: Icons.attach_money,
              title: 'Currency',
              subtitle: 'Change default currency',
              gradientColors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
              onTap: () {
                Navigator.pushNamed(context, '/currency-settings');
              },
            ),

            SizedBox(height: responsive.sp24),

            _buildSectionHeader('Notifications'),
            SizedBox(height: responsive.sp12),

            _buildSettingCard(
              icon: Icons.notifications_outlined,
              title: 'Notification Settings',
              subtitle: 'Manage notification preferences',
              gradientColors: [Color(0xFFFF6B6B), Color(0xFFEE5A6F)],
              onTap: () {
                Navigator.pushNamed(context, '/notification-settings');
              },
            ),


            SizedBox(height: responsive.sp24),

            // Subscription Section
            _buildSectionHeader('Subscription'),
            SizedBox(height: responsive.sp12),

            _buildSettingCard(
              icon: authProvider.isPremium ? Icons.star : Icons.upgrade,
              title: authProvider.isPremium ? 'Manage Subscription' : 'Upgrade to Premium',
              subtitle: authProvider.isPremium
                  ? 'View and manage your subscription'
                  : 'Unlock all premium features',
              gradientColors: [Color(0xFFFFD700), Color(0xFFFFA500)],
              onTap: () {
                Navigator.pushNamed(context, '/subscription');
              },
            ),

            SizedBox(height: responsive.sp24),

            // About Section
            _buildSectionHeader('About'),
            SizedBox(height: responsive.sp12),

            _buildSettingCard(
              icon: Icons.info_outline,
              title: 'About Flow Finance',
              subtitle: 'Version 1.0.0',
              gradientColors: [Color(0xFF2196F3), Color(0xFF1976D2)],
              onTap: () {
                _showAboutDialog(context);
              },
            ),

            SizedBox(height: responsive.sp8),

            _buildSettingCard(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              subtitle: 'View our privacy policy',
              gradientColors: [Color(0xFF9C27B0), Color(0xFF7B1FA2)],
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Privacy policy coming soon!',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                    backgroundColor: Color(0xFF667eea),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),

            SizedBox(height: responsive.sp8),

            _buildSettingCard(
              icon: Icons.description_outlined,
              title: 'Terms of Service',
              subtitle: 'View terms and conditions',
              gradientColors: [Color(0xFF00BCD4), Color(0xFF0097A7)],
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Terms of service coming soon!',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                    backgroundColor: Color(0xFF667eea),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),

            SizedBox(height: responsive.sp32),

            // Logout Button
            Container(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => _showLogoutDialog(context),
                icon: Icon(Icons.logout, color: Colors.white),
                label: Text(
                  'Logout',
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  ),
                  elevation: 4,
                ),
              ),
            ),

            SizedBox(height: responsive.sp32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final responsive = ResponsiveHelper(context);
    return Padding(
      padding: EdgeInsets.only(left: 8),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: responsive.fs18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF333333),
        ),
      ),
    );
  }

  Widget _buildSettingCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    final responsive = ResponsiveHelper(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
      child: Container(
        padding: responsive.padding(all: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 4,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: responsive.padding(all: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
                borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
              ),
              child: Icon(icon, color: Colors.white, size: responsive.icon24),
            ),
            SizedBox(width: responsive.sp16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: responsive.icon16,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showAboutDialog(BuildContext context) {
    final responsive = ResponsiveHelper(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
        ),
        title: Row(
          children: [
            Container(
              padding: responsive.padding(all: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.account_balance_wallet, color: Colors.white, size: responsive.icon24),
            ),
            SizedBox(width: responsive.sp12),
            Text(
              'Flow Finance',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version 1.0.0',
              style: GoogleFonts.poppins(
                fontSize: responsive.fs14,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: responsive.sp16),
            Text(
              'Flow Finance is your personal finance management app with AI-powered insights and budget tracking.',
              style: GoogleFonts.poppins(fontSize: responsive.fs14),
            ),
            SizedBox(height: responsive.sp16),
            Text(
              '© 2025 Flow Finance. All rights reserved.',
              style: GoogleFonts.poppins(
                fontSize: responsive.fs12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: GoogleFonts.poppins(
                color: Color(0xFF667eea),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final responsive = ResponsiveHelper(context);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
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
                Navigator.pushReplacementNamed(context, '/login');
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