import 'package:flutter/material.dart';
import 'package:frontend/providers/budget_provider.dart';
import 'package:frontend/screens/budgets/budget_detail_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/notification.dart';
import '../../providers/notification_provider.dart';
import '../../providers/goal_provider.dart';
import '../../widgets/app_list_row.dart';
import '../goals/goal_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshNotifications();
    });
  }

  Future<void> _refreshNotifications() async {
    final notificationProvider =
        Provider.of<NotificationProvider>(context, listen: false);
    await notificationProvider.fetchNotifications();
  }

  IconData _getNotificationIcon(NotificationType type) {
    switch (type) {
      case NotificationType.goal_achieved:
        return Icons.emoji_events_rounded;
      case NotificationType.goal_progress:
        return Icons.trending_up_rounded;
      case NotificationType.goal_milestone:
        return Icons.star_rounded;
      case NotificationType.goal_approaching_date:
        return Icons.event_rounded;
      case NotificationType.budget_started:
        return Icons.play_circle_filled_rounded;
      case NotificationType.budget_ending_soon:
        return Icons.access_time_rounded;
      case NotificationType.budget_threshold:
        return Icons.warning_amber_rounded;
      case NotificationType.budget_exceeded:
        return Icons.error_rounded;
      case NotificationType.budget_auto_created:
        return Icons.autorenew_rounded;
      case NotificationType.budget_now_active:
        return Icons.check_circle_rounded;
      case NotificationType.large_transaction:
        return Icons.payments_rounded;
      case NotificationType.unusual_spending:
        return Icons.trending_up_rounded;
      case NotificationType.payment_reminder:
        return Icons.notifications_active_rounded;
      case NotificationType.recurring_transaction_created: // ADD
        return Icons.repeat_rounded;
      case NotificationType.recurring_transaction_ended: // ADD
        return Icons.repeat_one_rounded;
      case NotificationType.recurring_transaction_disabled: // ADD
        return Icons.repeat_on_rounded;
      case NotificationType.weekly_insights_generated:
        return Icons.insights_rounded;
      case NotificationType.monthly_insights_generated: // NEW
        return Icons.calendar_month_rounded;
      case NotificationType.system_broadcast: // NEW
        return Icons.campaign_rounded;
      case NotificationType.admin_announcement: // NEW
        return Icons.announcement_rounded;
    }
  }

  // Type-tinted icon colours, mapped onto the jade design system's semantic
  // slots (primary = positive/routine, tertiary = attention, error =
  // critical, info = date/reminder, onSurfaceVariant = neutral/ended) so
  // every colour also adapts correctly in dark mode.
  Color _getNotificationColor(NotificationType type) {
    final scheme = Theme.of(context).colorScheme;
    switch (type) {
      case NotificationType.goal_achieved:
        return scheme.tertiary;
      case NotificationType.goal_progress:
        return scheme.primary;
      case NotificationType.goal_milestone:
        return AppTheme.starFor(context);
      case NotificationType.goal_approaching_date:
        return AppTheme.infoFor(context);
      case NotificationType.budget_started:
        return scheme.primary;
      case NotificationType.budget_ending_soon:
        return scheme.tertiary;
      case NotificationType.budget_threshold:
        return scheme.tertiary;
      case NotificationType.budget_exceeded:
        return scheme.error;
      case NotificationType.budget_auto_created:
        return scheme.primary;
      case NotificationType.budget_now_active:
        return scheme.primary;
      case NotificationType.large_transaction:
        return scheme.tertiary;
      case NotificationType.unusual_spending:
        return scheme.error;
      case NotificationType.payment_reminder:
        return AppTheme.infoFor(context);
      case NotificationType.recurring_transaction_created: // ADD
        return scheme.primary;
      case NotificationType.recurring_transaction_ended: // ADD
        return scheme.onSurfaceVariant;
      case NotificationType.recurring_transaction_disabled: // ADD
        return scheme.tertiary;
      case NotificationType.weekly_insights_generated:
        return scheme.primary;
      case NotificationType.monthly_insights_generated: // NEW
        return AppTheme.infoFor(context);
      case NotificationType.system_broadcast: // NEW
        return scheme.primary;
      case NotificationType.admin_announcement: // NEW
        return scheme.tertiary;
    }
  }

  Future<void> _handleNotificationTap(AppNotification notification) async {
    final notificationProvider =
        Provider.of<NotificationProvider>(context, listen: false);

    // Mark as read
    if (!notification.isRead) {
      await notificationProvider.markAsRead(notification.id);
    }

    // Navigate based on notification type
    if (notification.type.name.startsWith('budget_') && notification.goalId != null) {
      // Budget notification
      final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);
      final budget = await budgetProvider.getBudget(notification.goalId!);

      if (budget != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BudgetDetailScreen(budget: budget),
          ),
        ).then((_) => _refreshNotifications());
      }
    } else if (notification.type.name.startsWith('goal_') && notification.goalId != null) {
      // Goal notification
      final goalProvider = Provider.of<GoalProvider>(context, listen: false);
      final goal = await goalProvider.getGoal(notification.goalId!);

      if (goal != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GoalDetailScreen(goal: goal),
          ),
        ).then((_) => _refreshNotifications());
      }
    } else if (notification.type == NotificationType.large_transaction ||
        notification.type == NotificationType.unusual_spending ||
        notification.type == NotificationType.payment_reminder ||
        notification.type == NotificationType.recurring_transaction_created ||
        notification.type == NotificationType.recurring_transaction_ended ||
        notification.type == NotificationType.recurring_transaction_disabled) {
      // Transaction notifications - navigate to transactions list
      Navigator.pushNamed(context, '/transactions').then((_) => _refreshNotifications());
    } else if (notification.type == NotificationType.weekly_insights_generated ||
        notification.type == NotificationType.monthly_insights_generated) {
      // Navigate to insights screen
      Navigator.pushNamed(context, '/insights').then((_) => _refreshNotifications());
    } else if (notification.type == NotificationType.system_broadcast || // NEW
        notification.type == NotificationType.admin_announcement) {
      // NEW
      // Broadcast notifications - just dismiss or show detail
      // No specific navigation needed
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationProvider = Provider.of<NotificationProvider>(context);
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.notifications),
        actions: [
          if (notificationProvider.unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () async {
                  await notificationProvider.markAllAsRead();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(localizations.markedAsRead)),
                  );
                },
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: Text(localizations.markAllRead, style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshNotifications,
        child: notificationProvider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : notificationProvider.notifications.isEmpty
                ? _buildEmptyState(context)
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Column(
                          children: [
                            for (var i = 0; i < notificationProvider.notifications.length; i++) ...[
                              if (i > 0) const Divider(),
                              _buildNotificationCard(notificationProvider.notifications[i]),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: Text(
                          'Swipe a notification to delete it',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  String _buildSubtitle(AppNotification notification) {
    final parts = <String>[notification.message];
    if (notification.goalName != null) parts.add(notification.goalName!);
    if (notification.currency != null) parts.add(notification.getCurrencySymbol());
    return parts.join('  ·  ');
  }

  Widget _buildNotificationCard(AppNotification notification) {
    final icon = _getNotificationIcon(notification.type);
    final color = _getNotificationColor(notification.type);
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: scheme.error,
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (direction) async {
        final notificationProvider =
            Provider.of<NotificationProvider>(context, listen: false);
        await notificationProvider.deleteNotification(notification.id);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.notificationDeleted),
            action: SnackBarAction(
              label: localizations.undo,
              textColor: AppTheme.snackAccent,
              onPressed: () {
                // Refresh to restore
                _refreshNotifications();
              },
            ),
          ),
        );
      },
      child: Container(
        color: notification.isRead ? Colors.transparent : scheme.primaryContainer.withValues(alpha: 0.16),
        child: AppListRow(
          icon: icon,
          iconBg: color.withValues(alpha: 0.15),
          iconColor: color,
          title: notification.title,
          subtitle: _buildSubtitle(notification),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!notification.isRead)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                    ),
                  Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context), size: 20),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _formatTimestamp(notification.createdAt),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          onTap: () => _handleNotificationTap(notification),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM dd, yyyy').format(timestamp);
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.notifications_none_rounded, size: 48, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 24),
            Text(
              localizations.noNotificationsYet,
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              localizations.notifyGoalsProgress,
              style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
