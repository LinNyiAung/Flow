import 'package:flutter/material.dart';
import 'package:frontend/screens/settings/change_password_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/app_list_row.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../providers/notification_provider.dart';
import '../auth/login_screen.dart';
import 'edit_profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final user = authProvider.user;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final localizations = AppLocalizations.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(localizations.settings),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, notificationProvider, child) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_rounded),
                      onPressed: () {
                        Navigator.pushNamed(context, '/notifications').then((_) {
                          notificationProvider.fetchUnreadCount();
                        });
                      },
                    ),
                    if (notificationProvider.unreadCount > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            notificationProvider.unreadCount > 9 ? '9+' : '${notificationProvider.unreadCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Profile Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: scheme.primaryContainer,
                        child: Text(
                          user?.name != null && user!.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      if (authProvider.isPremium)
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: scheme.tertiary,
                              shape: BoxShape.circle,
                              border: Border.all(color: scheme.surface, width: 2),
                            ),
                            child: const Icon(Icons.star_rounded, color: Colors.white, size: 12),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.name ?? 'User', style: textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          user?.email ?? '',
                          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: authProvider.isPremium ? scheme.tertiaryContainer : scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                authProvider.isPremium ? Icons.star_rounded : Icons.lock_rounded,
                                size: 12,
                                color: authProvider.isPremium ? scheme.onTertiaryContainer : scheme.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                authProvider.isPremium ? 'Premium Member' : 'Free Plan',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: authProvider.isPremium ? scheme.onTertiaryContainer : scheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (authProvider.isPremium && authProvider.subscriptionExpiresAt != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Expires: ${_formatDate(authProvider.subscriptionExpiresAt!)}',
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          _buildSectionHeader(context, localizations.account),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                AppListRow(
                  icon: Icons.person_rounded,
                  title: localizations.editProfile,
                  subtitle: localizations.updateYourName,
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => EditProfileScreen()),
                    );
                    if (result == true) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(localizations.profileUpdatedSuccessfully)),
                      );
                    }
                  },
                  trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
                ),
                const Divider(),
                AppListRow(
                  icon: Icons.lock_rounded,
                  title: localizations.changePassword,
                  subtitle: localizations.updateYourPassword,
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ChangePasswordScreen()),
                    );
                    if (result == true) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(localizations.passwordChangedSuccessfully)),
                      );
                    }
                  },
                  trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
                ),
                const Divider(),
                AppListRow(
                  icon: Icons.language_rounded,
                  title: localizations.language,
                  subtitle: languageCode == 'my' ? 'မြန်မာ' : 'English',
                  onTap: () {
                    Navigator.pushNamed(context, '/language-settings');
                  },
                  trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
                ),
                const Divider(),
                AppListRow(
                  icon: Icons.payments_rounded,
                  title: localizations.currency,
                  subtitle: authProvider.defaultCurrency.displayName,
                  onTap: () {
                    Navigator.pushNamed(context, '/currency-settings');
                  },
                  trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          _buildSectionHeader(context, localizations.appearance),
          const SizedBox(height: 10),
          Card(
            child: AppListRow(
              icon: Icons.dark_mode_rounded,
              title: localizations.theme,
              subtitle: _themeModeLabel(localizations, themeProvider.themeMode),
              onTap: () {
                Navigator.pushNamed(context, '/theme-settings');
              },
              trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
            ),
          ),

          const SizedBox(height: 24),

          _buildSectionHeader(context, localizations.notifications),
          const SizedBox(height: 10),
          Card(
            child: AppListRow(
              icon: Icons.notifications_active_rounded,
              title: localizations.notificationSettings,
              subtitle: localizations.manageNotificationPreferences,
              onTap: () {
                Navigator.pushNamed(context, '/notification-settings');
              },
              trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
            ),
          ),

          const SizedBox(height: 24),

          _buildSectionHeader(context, localizations.subscription),
          const SizedBox(height: 10),
          Card(
            child: AppListRow(
              icon: authProvider.isPremium ? Icons.star_rounded : Icons.upgrade_rounded,
              iconBg: scheme.tertiaryContainer,
              iconColor: scheme.onTertiaryContainer,
              title: authProvider.isPremium ? localizations.manageSubscription : localizations.upgradeToPremium,
              subtitle: authProvider.isPremium
                  ? localizations.viewManageSubscription
                  : localizations.unlockPremiumFeatures,
              onTap: () {
                Navigator.pushNamed(context, '/subscription');
              },
              trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
            ),
          ),

          const SizedBox(height: 24),

          _buildSectionHeader(context, localizations.about),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                AppListRow(
                  icon: Icons.info_rounded,
                  title: localizations.aboutToePwar,
                  subtitle: 'Version 1.0.0',
                  onTap: () => _showAboutDialog(context),
                ),
                const Divider(),
                AppListRow(
                  icon: Icons.privacy_tip_rounded,
                  title: 'Privacy Policy',
                  subtitle: 'View our privacy policy',
                  onTap: () {
                    Navigator.pushNamed(context, '/privacy-policy');
                  },
                  trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
                ),
                const Divider(),
                AppListRow(
                  icon: Icons.description_rounded,
                  title: 'Terms and Conditions',
                  subtitle: 'View terms and conditions',
                  onTap: () {
                    Navigator.pushNamed(context, '/terms-conditions');
                  },
                  trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
                ),
                const Divider(),
                AppListRow(
                  icon: Icons.feedback_rounded,
                  title: localizations.sendFeedback,
                  subtitle: localizations.feedbackDesc,
                  onTap: () {
                    Navigator.pushNamed(context, '/feedback');
                  },
                  trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Logout Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => _showLogoutDialog(context),
              icon: Icon(Icons.logout_rounded, color: scheme.error),
              label: Text(
                localizations.drawerLogout,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.error),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: scheme.error),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _themeModeLabel(AppLocalizations localizations, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return localizations.themeLight;
      case ThemeMode.dark:
        return localizations.themeDark;
      case ThemeMode.system:
        return localizations.themeSystem;
    }
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showAboutDialog(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.savings_rounded, color: scheme.onPrimaryContainer, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Toe Pwar'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 1.0.0', style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            const Text(
              'Toe Pwar is your personal finance management app with AI-powered insights and budget tracking.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Text(
              '© 2025 Toe Pwar. All rights reserved.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.close),
          ),
        ],
      ),
    );
  }

  // Matches the app's other destructive-confirmation sheets (e.g. Delete
  // Budget) — icon circle, title, message, full-width filled action, then
  // a plain Cancel below it — instead of a plain AlertDialog.
  void _showLogoutDialog(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: scheme.errorContainer, shape: BoxShape.circle),
            child: Icon(Icons.logout_rounded, color: scheme.error, size: 26),
          ),
          const SizedBox(height: 14),
          Text(localizations.drawerLogout, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            localizations.dialogLogoutConfirm,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              onPressed: () {
                Navigator.pop(sheetContext);
                Provider.of<AuthProvider>(context, listen: false).logout();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => LoginScreen()),
                );
              },
              child: Text(localizations.drawerLogout),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(localizations.dialogCancel),
            ),
          ),
        ],
      ),
    );
  }
}
