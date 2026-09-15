import 'package:flutter/material.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/status_pill.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/home/home_screen.dart';
import '../screens/transactions/transactions_list_screen.dart';
import 'package:frontend/services/responsive_helper.dart';

class _DrawerNavItem {
  const _DrawerNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.badgeText,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  /// Per-item badge copy (mockup: "3 NEW" / "TRY FREE" / "FREE MONTH" — not
  /// a generic "PREMIUM" pill). Null means no badge.
  final String? badgeText;
}

class AppDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final localizations = AppLocalizations.of(context);
    final responsive = ResponsiveHelper(context);
    final scheme = Theme.of(context).colorScheme;
    final currentRoute = ModalRoute.of(context)?.settings.name;
    final isHome = currentRoute == '/';
    final isPremium = authProvider.isPremium;

    void go(String routeName) {
      Navigator.pop(context);
      Navigator.pushNamed(context, routeName);
    }

    // Order, icons and route keys mirror the mockup's `nav` list (lines
    // 3195-3212): Dashboard, Transactions, Budgets, Goals, AI assistant,
    // Inflow analytics, Outflow analytics, Reports, Insights, Premium.
    final navItems = <_DrawerNavItem>[
      _DrawerNavItem(
        icon: Icons.space_dashboard_rounded,
        label: localizations.dashboard,
        isActive: isHome,
        onTap: () {
          Navigator.pop(context);
          if (!isHome) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => HomeScreen()),
            );
          }
        },
      ),
      _DrawerNavItem(
        icon: Icons.receipt_long_rounded,
        label: localizations.transactions,
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TransactionsListScreen()),
          );
        },
      ),
      _DrawerNavItem(
        icon: Icons.savings_rounded,
        label: localizations.budgets,
        isActive: currentRoute == '/budgets',
        onTap: () => go('/budgets'),
      ),
      _DrawerNavItem(
        icon: Icons.flag_rounded,
        label: localizations.goals,
        isActive: currentRoute == '/goals',
        onTap: () => go('/goals'),
      ),
      _DrawerNavItem(
        icon: Icons.forum_rounded,
        label: localizations.aiAssistant,
        isActive: currentRoute == '/ai-chat',
        badgeText: !isPremium ? 'TRY FREE' : null,
        onTap: () => go('/ai-chat'),
      ),
      _DrawerNavItem(
        icon: Icons.trending_up_rounded,
        label: localizations.inflowAnalytics,
        isActive: currentRoute == '/inflow-analytics',
        onTap: () => go('/inflow-analytics'),
      ),
      _DrawerNavItem(
        icon: Icons.pie_chart_rounded,
        label: localizations.outflowAnalytics,
        isActive: currentRoute == '/outflow-analytics',
        onTap: () => go('/outflow-analytics'),
      ),
      _DrawerNavItem(
        icon: Icons.assessment_rounded,
        label: localizations.financialReports,
        isActive: currentRoute == '/reports',
        onTap: () => go('/reports'),
      ),
      _DrawerNavItem(
        icon: Icons.lightbulb_rounded,
        label: localizations.aiInsights,
        isActive: currentRoute == '/insights',
        badgeText: !isPremium ? '3 NEW' : null,
        onTap: () => go('/insights'),
      ),
      _DrawerNavItem(
        icon: Icons.workspace_premium_rounded,
        label: localizations.subscription,
        isActive: currentRoute == '/subscription',
        badgeText: !isPremium ? 'FREE MONTH' : null,
        onTap: () => go('/subscription'),
      ),
    ];

    return Drawer(
      child: SafeArea(
        child: Column(
          children: <Widget>[
            // Profile header
            Padding(
              padding: responsive.padding(left: 20, right: 20, top: 18, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: responsive.iconSize(mobile: 52),
                        height: responsive.iconSize(mobile: 52),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          user?.name != null && user!.name.isNotEmpty
                              ? user.name[0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            fontSize: responsive.fs20,
                            fontWeight: FontWeight.w800,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      if (isPremium) ...[
                        SizedBox(width: responsive.sp8),
                        StatusPill(
                          label: localizations.premium.toUpperCase(),
                          background: scheme.tertiaryContainer,
                          foreground: scheme.tertiary,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: responsive.sp12),
                  Text(
                    user?.name ?? '',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: responsive.fontSize(mobile: 17),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    user?.email ?? '',
                    style: TextStyle(
                      fontSize: responsive.fs12,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isPremium && authProvider.subscriptionExpiresAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${localizations.expiresOn}: ${_formatDate(authProvider.subscriptionExpiresAt!)}',
                        style: TextStyle(
                          fontSize: responsive.fs11,
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),

            // Navigation items
            Expanded(
              child: ListView(
                padding: responsive.padding(horizontal: 12),
                children: [
                  for (final item in navItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: _DrawerRow(item: item, responsive: responsive),
                    ),
                ],
              ),
            ),

            Padding(
              padding: responsive.padding(horizontal: 20),
              child: Divider(height: 1),
            ),

            // Settings + logout
            Padding(
              padding: responsive.padding(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  _DrawerRow(
                    item: _DrawerNavItem(
                      icon: Icons.settings_rounded,
                      label: localizations.settings,
                      isActive: currentRoute == '/settings',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/settings');
                      },
                    ),
                    responsive: responsive,
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () {
                      Navigator.pop(context);
                      _showLogoutDialog(context);
                    },
                    child: Padding(
                      padding: responsive.padding(horizontal: 16, vertical: 13),
                      child: Row(
                        children: [
                          Icon(
                            Icons.logout_rounded,
                            size: responsive.iconSize(mobile: 22),
                            color: scheme.error,
                          ),
                          SizedBox(width: responsive.spacing(mobile: 14)),
                          Flexible(
                            child: Text(
                              localizations.drawerLogout,
                              style: TextStyle(
                                fontSize: responsive.fs14,
                                fontWeight: FontWeight.w600,
                                color: scheme.error,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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

  // Matches the app's other destructive-confirmation sheets (e.g. Delete
  // Budget) — icon circle, title, message, full-width filled action, then
  // a plain Cancel below it — instead of a plain AlertDialog. Also fixes
  // an existing dark-mode gap this dialog never had: filled buttons need
  // errorContainer/onErrorContainer, not the bare `error` role, which is a
  // light TEXT tone in dark mode rather than a fill-safe solid colour.
  void _showLogoutDialog(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Resolved up front: the drawer closes itself right before this sheet
    // opens, so by the time the user taps "Log out" the drawer's own
    // context is already unmounted. Grabbing the navigator and provider now
    // (still valid, since the drawer is only mid-close-animation) lets the
    // button act on them later without redoing a lookup on a dead context.
    final navigator = Navigator.of(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

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
                authProvider.logout();
                navigator.pushReplacement(
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

// Pill-shaped nav row — primaryContainer fill when [_DrawerNavItem.isActive],
// a tonal badge (item-specific copy, not a padlock) for gated items.
class _DrawerRow extends StatelessWidget {
  const _DrawerRow({required this.item, required this.responsive});

  final _DrawerNavItem item;
  final ResponsiveHelper responsive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = item.isActive ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    return Material(
      color: item.isActive ? scheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: item.onTap,
        child: Padding(
          padding: responsive.padding(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(item.icon, size: responsive.iconSize(mobile: 22), color: fg),
              SizedBox(width: responsive.spacing(mobile: 14)),
              Expanded(
                child: Text(
                  item.label,
                  // Mockup applies one `ink` colour to the whole row (icon
                  // + label together), not a brighter tone just for the
                  // text — reuse `fg` here instead of `scheme.onSurface`.
                  style: TextStyle(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.badgeText != null)
                StatusPill(
                  label: item.badgeText!,
                  background: scheme.tertiaryContainer,
                  foreground: scheme.tertiary,
                  dense: true,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
