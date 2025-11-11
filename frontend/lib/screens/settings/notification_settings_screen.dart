import 'package:flutter/material.dart';
import 'package:frontend/models/notification.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  @override
  _NotificationSettingsScreenState createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _notificationsEnabled = false;
  final _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _checkPermissionStatus();
  }

  Future<void> _checkPermissionStatus() async {
    final status = await Permission.notification.status;
    setState(() {
      _notificationsEnabled = status.isGranted;
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      final granted = await _notificationService.requestPermissions();
      if (granted) {
        setState(() {
          _notificationsEnabled = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Notifications enabled!',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _notificationsEnabled = false;
        });
        // Show dialog to open app settings
        _showSettingsDialog();
      }
    } else {
      // Can't disable from app, must go to system settings
      _showSettingsDialog();
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Notification Settings',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'To change notification settings, please go to your device settings.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF667eea),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Open Settings',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testNotification() async {
    await _notificationService.showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Test Notification 🎉',
      body: 'This is a test notification from Flow Finance!',
      type: NotificationType.goal_progress,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Test notification sent!',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notification Settings',
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
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF667eea).withOpacity(0.1), Colors.white],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.all(20),
          children: [
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 2,
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Push Notifications',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Receive goal updates',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: _notificationsEnabled,
                        onChanged: _toggleNotifications,
                        activeColor: Color(0xFF667eea),
                      ),
                    ],
                  ),
                  if (_notificationsEnabled) ...[
                    Divider(height: 32),
                    Text(
                      'You\'ll receive notifications for:',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333),
                      ),
                    ),
                    SizedBox(height: 12),

                    // Goal Notifications Header
                    Text(
                      'Goals',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF667eea),
                      ),
                    ),
                    SizedBox(height: 8),
                    _buildNotificationTypeItem(
                      icon: Icons.trending_up,
                      color: Color(0xFF4CAF50),
                      title: 'Goal Progress',
                      description: '25%, 50%, 75% milestones',
                    ),
                    SizedBox(height: 8),
                    _buildNotificationTypeItem(
                      icon: Icons.star,
                      color: Color(0xFFFF9800),
                      title: 'Milestone Reached',
                      description: 'Every \$1,000 saved',
                    ),
                    SizedBox(height: 8),
                    _buildNotificationTypeItem(
                      icon: Icons.event,
                      color: Color(0xFF2196F3),
                      title: 'Deadline Approaching',
                      description: '14, 7, and 3 days before',
                    ),
                    SizedBox(height: 8),
                    _buildNotificationTypeItem(
                      icon: Icons.emoji_events,
                      color: Color(0xFFFFD700),
                      title: 'Goal Achieved',
                      description: 'Congratulations!',
                    ),

                    SizedBox(height: 16),
                    Divider(),
                    SizedBox(height: 8),

                    // Budget Notifications Header
                    Text(
                      'Budgets',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF667eea),
                      ),
                    ),
                    SizedBox(height: 8),
                    _buildNotificationTypeItem(
                      icon: Icons.play_circle_filled,
                      color: Color(0xFF4CAF50),
                      title: 'Budget Started',
                      description: 'New budget period begins',
                    ),
                    SizedBox(height: 8),
                    _buildNotificationTypeItem(
                      icon: Icons.access_time,
                      color: Color(0xFFFF9800),
                      title: 'Budget Ending Soon',
                      description: '3 days before period ends',
                    ),
                    SizedBox(height: 8),
                    _buildNotificationTypeItem(
                      icon: Icons.warning_amber_rounded,
                      color: Color(0xFFFF9800),
                      title: 'Budget Threshold',
                      description: '80% of budget spent',
                    ),
                    SizedBox(height: 8),
                    _buildNotificationTypeItem(
                      icon: Icons.error,
                      color: Color(0xFFFF5722),
                      title: 'Budget Exceeded',
                      description: 'Over budget limit',
                    ),
                    SizedBox(height: 8),
                    _buildNotificationTypeItem(
                      icon: Icons.autorenew,
                      color: Color(0xFF667eea),
                      title: 'Auto-Created Budget',
                      description: 'New budget created automatically',
                    ),

                    SizedBox(height: 16),
                    Divider(),
                    SizedBox(height: 8),

                    // Transaction Notifications Header
                    Text(
                      'Transactions',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF667eea),
                      ),
                    ),
                    SizedBox(height: 8),
                    _buildNotificationTypeItem(
                      icon: Icons.payments,
                      color: Color(0xFFFF9800),
                      title: 'Large Transaction',
                      description: 'Unusually large expenses',
                    ),
                    SizedBox(height: 8),
                    _buildNotificationTypeItem(
                      icon: Icons.trending_up,
                      color: Color(0xFFFF5722),
                      title: 'Unusual Spending',
                      description: 'Spending spikes detected',
                    ),
                    SizedBox(height: 8),
                    _buildNotificationTypeItem(
                      icon: Icons.notifications_active,
                      color: Color(0xFF2196F3),
                      title: 'Payment Reminders',
                      description: 'Recurring payment alerts',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTypeItem({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF333333),
                ),
              ),
              Text(
                description,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
