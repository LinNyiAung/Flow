import 'package:flutter/material.dart';
import 'package:frontend/providers/budget_provider.dart';
import 'package:frontend/screens/budgets/budget_detail_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/notification.dart';
import '../../providers/notification_provider.dart';
import '../../providers/goal_provider.dart';
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
      return Icons.emoji_events;
    case NotificationType.goal_progress:
      return Icons.trending_up;
    case NotificationType.goal_milestone:
      return Icons.star;
    case NotificationType.goal_approaching_date:
      return Icons.event;
    case NotificationType.budget_started:
      return Icons.play_circle_filled;
    case NotificationType.budget_ending_soon:
      return Icons.access_time;
    case NotificationType.budget_threshold:
      return Icons.warning_amber_rounded;
    case NotificationType.budget_exceeded:
      return Icons.error;
    case NotificationType.budget_auto_created:
      return Icons.autorenew;
    case NotificationType.budget_now_active:
      return Icons.check_circle;
    case NotificationType.large_transaction:      // ADD THIS
      return Icons.payments;
    case NotificationType.unusual_spending:       // ADD THIS
      return Icons.trending_up;
    case NotificationType.payment_reminder:       // ADD THIS
      return Icons.notifications_active;
  }
}

Color _getNotificationColor(NotificationType type) {
  switch (type) {
    case NotificationType.goal_achieved:
      return Color(0xFFFFD700);
    case NotificationType.goal_progress:
      return Color(0xFF4CAF50);
    case NotificationType.goal_milestone:
      return Color(0xFFFF9800);
    case NotificationType.goal_approaching_date:
      return Color(0xFF2196F3);
    case NotificationType.budget_started:
      return Color(0xFF4CAF50);
    case NotificationType.budget_ending_soon:
      return Color(0xFFFF9800);
    case NotificationType.budget_threshold:
      return Color(0xFFFF9800);
    case NotificationType.budget_exceeded:
      return Color(0xFFFF5722);
    case NotificationType.budget_auto_created:
      return Color(0xFF667eea);
    case NotificationType.budget_now_active:
      return Color(0xFF4CAF50);
    case NotificationType.large_transaction:      // ADD THIS
      return Color(0xFFFF9800);
    case NotificationType.unusual_spending:       // ADD THIS
      return Color(0xFFFF5722);
    case NotificationType.payment_reminder:       // ADD THIS
      return Color(0xFF2196F3);
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
             notification.type == NotificationType.payment_reminder) {
    // Transaction notifications - navigate to transactions list
    Navigator.pushNamed(context, '/transactions').then((_) => _refreshNotifications());
  }
}

  @override
  Widget build(BuildContext context) {
    final notificationProvider = Provider.of<NotificationProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Color(0xFF333333)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (notificationProvider.unreadCount > 0)
            TextButton.icon(
              onPressed: () async {
                await notificationProvider.markAllAsRead();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'All notifications marked as read',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                    backgroundColor: Color(0xFF4CAF50),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: Icon(Icons.done_all, size: 18),
              label: Text('Mark all read', style: GoogleFonts.poppins(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: Color(0xFF667eea),
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
        child: RefreshIndicator(
          onRefresh: _refreshNotifications,
          color: Color(0xFF667eea),
          child: notificationProvider.isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                  ),
                )
              : notificationProvider.notifications.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: notificationProvider.notifications.length,
                      itemBuilder: (context, index) {
                        final notification =
                            notificationProvider.notifications[index];
                        return _buildNotificationCard(notification);
                      },
                    ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(AppNotification notification) {
    final icon = _getNotificationIcon(notification.type);
    final color = _getNotificationColor(notification.type);

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) async {
        final notificationProvider =
            Provider.of<NotificationProvider>(context, listen: false);
        await notificationProvider.deleteNotification(notification.id);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Notification deleted',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'UNDO',
              textColor: Colors.white,
              onPressed: () {
                // Refresh to restore
                _refreshNotifications();
              },
            ),
          ),
        );
      },
      child: GestureDetector(
        onTap: () => _handleNotificationTap(notification),
        child: Container(
          margin: EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: notification.isRead
                ? Colors.white
                : Color(0xFF667eea).withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: notification.isRead
                  ? Colors.grey.withOpacity(0.2)
                  : Color(0xFF667eea).withOpacity(0.3),
              width: notification.isRead ? 1 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: notification.isRead
                                  ? FontWeight.w600
                                  : FontWeight.bold,
                              color: Color(0xFF333333),
                            ),
                          ),
                        ),
                        if (!notification.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Color(0xFF667eea),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      notification.message,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        SizedBox(width: 4),
                        Text(
                          _formatTimestamp(notification.createdAt),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                        if (notification.goalName != null) ...[
                          SizedBox(width: 12),
                          Icon(
                            Icons.flag,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              notification.goalName!,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
                size: 20,
              ),
            ],
          ),
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

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.notifications_none,
                size: 48,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 24),
            Text(
              'No notifications yet',
              style: GoogleFonts.poppins(
                fontSize: 18,
                color: Color(0xFF333333),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'We\'ll notify you about your financial goals progress',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}