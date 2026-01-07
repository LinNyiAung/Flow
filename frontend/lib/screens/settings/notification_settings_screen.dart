import 'package:flutter/material.dart';
import 'package:frontend/models/notification.dart';
import 'package:frontend/models/notification_preferences.dart';
import 'package:frontend/services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/localization_service.dart';
import '../../services/notification_service.dart';
import 'package:frontend/services/responsive_helper.dart';

class NotificationSettingsScreen extends StatefulWidget {
  @override
  _NotificationSettingsScreenState createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _notificationsEnabled = false;
  bool _isLoading = true;
  NotificationPreferences? _preferences;
  final _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _checkPermissionStatus();
    if (_notificationsEnabled) {
      await _loadPreferences();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _checkPermissionStatus() async {
    final status = await Permission.notification.status;
    setState(() {
      _notificationsEnabled = status.isGranted;
    });
  }

  Future<void> _loadPreferences() async {
    try {
      final response = await ApiService.getNotificationPreferences();
      setState(() {
        _preferences = response.preferences;
      });
    } catch (e) {
      print('Error loading preferences: $e');
    }
  }

  Future<void> _updatePreference(String key, bool value) async {
    if (_preferences == null) return;

    try {
      // Update locally first for immediate feedback
      setState(() {
        _preferences = _updatePreferenceValue(key, value);
      });

      // Update on server
      await ApiService.updateNotificationPreferences(
        preferences: {key: value},
      );
    } catch (e) {
      print('Error updating preference: $e');
      // Revert on error
      setState(() {
        _preferences = _updatePreferenceValue(key, !value);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to update preference',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  NotificationPreferences _updatePreferenceValue(String key, bool value) {
    return _preferences!.copyWith(
      goalProgress: key == 'goal_progress' ? value : _preferences!.goalProgress,
      goalMilestone: key == 'goal_milestone' ? value : _preferences!.goalMilestone,
      goalApproachingDate: key == 'goal_approaching_date' ? value : _preferences!.goalApproachingDate,
      goalAchieved: key == 'goal_achieved' ? value : _preferences!.goalAchieved,
      budgetStarted: key == 'budget_started' ? value : _preferences!.budgetStarted,
      budgetEndingSoon: key == 'budget_ending_soon' ? value : _preferences!.budgetEndingSoon,
      budgetThreshold: key == 'budget_threshold' ? value : _preferences!.budgetThreshold,
      budgetExceeded: key == 'budget_exceeded' ? value : _preferences!.budgetExceeded,
      budgetAutoCreated: key == 'budget_auto_created' ? value : _preferences!.budgetAutoCreated,
      budgetNowActive: key == 'budget_now_active' ? value : _preferences!.budgetNowActive,
      largeTransaction: key == 'large_transaction' ? value : _preferences!.largeTransaction,
      unusualSpending: key == 'unusual_spending' ? value : _preferences!.unusualSpending,
      paymentReminder: key == 'payment_reminder' ? value : _preferences!.paymentReminder,
      recurringTransactionCreated: key == 'recurring_transaction_created' ? value : _preferences!.recurringTransactionCreated,
      recurringTransactionEnded: key == 'recurring_transaction_ended' ? value : _preferences!.recurringTransactionEnded,
      recurringTransactionDisabled: key == 'recurring_transaction_disabled' ? value : _preferences!.recurringTransactionDisabled,
      weeklyInsightsGenerated: key == 'weekly_insights_generated' ? value : _preferences!.weeklyInsightsGenerated,
    );
  }

  Future<void> _toggleNotifications(bool value) async {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    if (value) {
      final granted = await _notificationService.requestPermissions();
      if (granted) {
        setState(() => _notificationsEnabled = true);
        await _loadPreferences();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localizations.notificationsEnabled,
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(12))),
          ),
        );
      } else {
        setState(() => _notificationsEnabled = false);
        _showSettingsDialog();
      }
    } else {
      _showSettingsDialog();
    }
  }

  void _showSettingsDialog() {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(16))),
        title: Row(
          children: [
            Container(
              padding: responsive.padding(all: 8),
              decoration: BoxDecoration(
                color: Color(0xFF667eea).withOpacity(0.1),
                borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
              ),
              child: Icon(Icons.settings, color: Color(0xFF667eea)),
            ),
            SizedBox(width: responsive.sp12),
            Expanded(
              child: Text(
                localizations.notificationSettings,
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: responsive.fs18),
              ),
            ),
          ],
        ),
        content: Text(
          localizations.changeNotificationSettingsDes,
          style: GoogleFonts.poppins(fontSize: responsive.fs14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.dialogCancel, style: GoogleFonts.poppins(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF667eea),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(8))),
              elevation: 0,
            ),
            child: Text(localizations.openSettings, style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _testNotification() async {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    await _notificationService.showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: localizations.testNotification,
      body: localizations.testNotificationDes,
      type: NotificationType.goal_progress,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          localizations.testNotificationMsg,
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(12))),
      ),
    );
  }

  Future<void> _resetToDefaults() async {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(16))),
        title: Text(
          localizations.resetToDefaults,
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          localizations.enableAllNotificationTypes,
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.dialogCancel, style: GoogleFonts.poppins(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ApiService.resetNotificationPreferences();
                await _loadPreferences();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      localizations.notificationPreferencesReset,
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                    backgroundColor: Color(0xFF4CAF50),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      localizations.failedToResetPreferences,
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF667eea),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(8))),
            ),
            child: Text(localizations.reset, style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          localizations.notificationSettings,
          style: GoogleFonts.poppins(
            fontSize: responsive.fs20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Color(0xFF333333)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_notificationsEnabled && _preferences != null)
            IconButton(
              icon: Icon(Icons.refresh, color: Color(0xFF667eea)),
              onPressed: _resetToDefaults,
              tooltip: localizations.resetToDefaultsWQ,
            ),
        ],
      ),
      body: _isLoading
          ? Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
        ),
      )
          : Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF667eea).withOpacity(0.1), Colors.white],
          ),
        ),
        child: ListView(
          padding: responsive.padding(all: 20),
          children: [
            // Main Toggle Card
            Container(
              padding: responsive.padding(all: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
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
                    children: [
                      Container(
                        padding: responsive.padding(all: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                          ),
                          borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                        ),
                        child: Icon(
                          Icons.notifications_active,
                          color: Colors.white,
                          size: responsive.icon24,
                        ),
                      ),
                      SizedBox(width: responsive.sp16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizations.pushNotifications,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF333333),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              localizations.receiveUpdatesAboutFinances,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _notificationsEnabled,
                        onChanged: _toggleNotifications,
                        activeColor: Color(0xFF667eea),
                      ),
                    ],
                  ),

                  if (_notificationsEnabled) ...[
                    SizedBox(height: responsive.sp20),
                    Divider(),
                    SizedBox(height: responsive.sp20),

                    // Test Notification Button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _testNotification,
                        icon: Icon(Icons.send, size: responsive.icon18),
                        label: Text(localizations.sendTestNotification),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Color(0xFF667eea),
                          side: BorderSide(color: Color(0xFF667eea)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                          ),
                          padding: responsive.padding(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (_notificationsEnabled && _preferences != null) ...[
              SizedBox(height: responsive.sp24),

              // Info Card
              Container(
                padding: responsive.padding(all: 16),
                decoration: BoxDecoration(
                  color: Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  border: Border.all(
                    color: Color(0xFF2196F3).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF2196F3), size: responsive.icon24),
                    SizedBox(width: responsive.sp12),
                    Expanded(
                      child: Text(
                        localizations.customizeNotificationsReceive,
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs13,
                          color: Color(0xFF2196F3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: responsive.sp24),

              // Notification Types Header
              Padding(
                padding: EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  localizations.notificationTypes,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                ),
              ),

              // Goal Notifications Section
              _buildNotificationSection(
                title: localizations.goals,
                icon: Icons.flag,
                color: Color(0xFF4CAF50),
                notifications: [
                  _NotificationToggleInfo(
                    key: 'goal_progress',
                    icon: Icons.trending_up,
                    color: Color(0xFF4CAF50),
                    title: localizations.progressUpdates,
                    description: localizations.notifiedMilestones,
                    value: _preferences!.goalProgress,
                  ),
                  _NotificationToggleInfo(
                    key: 'goal_milestone',
                    icon: Icons.star,
                    color: Color(0xFFFF9800),
                    title: localizations.milestoneReached,
                    description: localizations.thousandSavedTowardsGoal,
                    value: _preferences!.goalMilestone,
                  ),
                  _NotificationToggleInfo(
                    key: 'goal_approaching_date',
                    icon: Icons.event,
                    color: Color(0xFF2196F3),
                    title: localizations.deadlineApproaching,
                    description: localizations.reminders,
                    value: _preferences!.goalApproachingDate,
                  ),
                  _NotificationToggleInfo(
                    key: 'goal_achieved',
                    icon: Icons.emoji_events,
                    color: Color(0xFFFFD700),
                    title: localizations.goalAchieved,
                    description: localizations.celebrate,
                    value: _preferences!.goalAchieved,
                  ),
                ],
              ),

              SizedBox(height: responsive.sp16),

              // Budget Notifications Section
              _buildNotificationSection(
                title: localizations.budgets,
                icon: Icons.account_balance_wallet,
                color: Color(0xFF667eea),
                notifications: [
                  _NotificationToggleInfo(
                    key: 'budget_started',
                    icon: Icons.play_circle_filled,
                    color: Color(0xFF4CAF50),
                    title: localizations.budgetStarted,
                    description: localizations.whenNewBudgetBegins,
                    value: _preferences!.budgetStarted,
                  ),
                  _NotificationToggleInfo(
                    key: 'budget_ending_soon',
                    icon: Icons.access_time,
                    color: Color(0xFFFF9800),
                    title: localizations.periodEndingSoon,
                    description: localizations.reminderBudgets,
                    value: _preferences!.budgetEndingSoon,
                  ),
                  _NotificationToggleInfo(
                    key: 'budget_threshold',
                    icon: Icons.warning_amber_rounded,
                    color: Color(0xFFFF9800),
                    title: localizations.budgetThreshold,
                    description: localizations.alertBudget,
                    value: _preferences!.budgetThreshold,
                  ),
                  _NotificationToggleInfo(
                    key: 'budget_exceeded',
                    icon: Icons.error,
                    color: Color(0xFFFF5722),
                    title: localizations.budgetExceeded,
                    description: localizations.whenOverBudgetLimit,
                    value: _preferences!.budgetExceeded,
                  ),
                  _NotificationToggleInfo(
                    key: 'budget_auto_created',
                    icon: Icons.autorenew,
                    color: Color(0xFF667eea),
                    title: localizations.autoCreatedBudget,
                    description: localizations.budgetCreatedAutomatically,
                    value: _preferences!.budgetAutoCreated,
                  ),
                  _NotificationToggleInfo(
                    key: 'budget_now_active',
                    icon: Icons.check_circle,
                    color: Color(0xFF4CAF50),
                    title: localizations.budgetNowActive,
                    description: localizations.whenBudgetBecomesActive,
                    value: _preferences!.budgetNowActive,
                  ),
                ],
              ),

              SizedBox(height: responsive.sp16),


              // Insights Notifications Section
              _buildNotificationSection(
                title: localizations.aiInsights,
                icon: Icons.account_balance_wallet,
                color: Color(0xFF667eea),
                notifications: [
                  _NotificationToggleInfo(
                    key: 'weekly_insights_generated',
                    icon: Icons.insights,
                    color: Color(0xFF667eea),
                    title: localizations.weeklyInsights, // Add to your localization
                    description: localizations.whenWeeklyInsightsReady, // Add to your localization
                    value: _preferences!.weeklyInsightsGenerated,
                  ),
                ],
              ),

              SizedBox(height: responsive.sp16),

              // Transaction Notifications Section
              _buildNotificationSection(
                title: localizations.transactions,
                icon: Icons.receipt_long,
                color: Color(0xFFFF6B6B),
                notifications: [
                  _NotificationToggleInfo(
                    key: 'large_transaction',
                    icon: Icons.payments,
                    color: Color(0xFFFF9800),
                    title: localizations.largeTransaction,
                    description: localizations.alertsLargeExpenses,
                    value: _preferences!.largeTransaction,
                  ),
                  _NotificationToggleInfo(
                    key: 'unusual_spending',
                    icon: Icons.trending_up,
                    color: Color(0xFFFF5722),
                    title: localizations.unusualSpending,
                    description: localizations.whenSpendingPatternsChange,
                    value: _preferences!.unusualSpending,
                  ),
                  _NotificationToggleInfo(
                    key: 'payment_reminder',
                    icon: Icons.notifications_active,
                    color: Color(0xFF2196F3),
                    title: localizations.paymentReminders,
                    description: localizations.upcomingPayments,
                    value: _preferences!.paymentReminder,
                  ),
                  _NotificationToggleInfo(
                    key: 'recurring_transaction_created',
                    icon: Icons.repeat,
                    color: Color(0xFF4CAF50),
                    title: localizations.recurringCreated,
                    description: localizations.whenRecurringTransactionsCreated,
                    value: _preferences!.recurringTransactionCreated,
                  ),
                  _NotificationToggleInfo(
                    key: 'recurring_transaction_ended',
                    icon: Icons.repeat_one,
                    color: Color(0xFF9E9E9E),
                    title: localizations.recurringEnded,
                    description: localizations.whenRecurringEnds,
                    value: _preferences!.recurringTransactionEnded,
                  ),
                  _NotificationToggleInfo(
                    key: 'recurring_transaction_disabled',
                    icon: Icons.repeat_on_rounded,
                    color: Color(0xFFFF9800),
                    title: localizations.recurringDisabled,
                    description: localizations.whenRecurrenceDisabled,
                    value: _preferences!.recurringTransactionDisabled,
                  ),
                ],
              ),

              SizedBox(height: responsive.sp32),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<_NotificationToggleInfo> notifications,
  }) {
    final responsive = ResponsiveHelper(context);
    return Container(
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
      child: Column(
        children: [
          // Section Header
          Container(
            padding: responsive.padding(all: 16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: responsive.icon20),
                SizedBox(width: responsive.sp12),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          // Notification Items
          ...notifications.map((notif) => _buildNotificationToggleItem(
            notif: notif,
            isLast: notif == notifications.last,
          )),
        ],
      ),
    );
  }

  Widget _buildNotificationToggleItem({
    required _NotificationToggleInfo notif,
    bool isLast = false,
  }) {
    final responsive = ResponsiveHelper(context);
    return Container(
      padding: responsive.padding(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
          bottom: BorderSide(
            color: Colors.grey.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: responsive.iconSize(mobile: 40),
            height: responsive.iconSize(mobile: 40),
            decoration: BoxDecoration(
              color: notif.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(notif.icon, color: notif.color, size: responsive.icon20),
          ),
          SizedBox(width: responsive.sp16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notif.title,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  notif.description,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs12,
                    color: Colors.grey[600],
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: responsive.sp12),
          Switch(
            value: notif.value,
            onChanged: (value) => _updatePreference(notif.key, value),
            activeColor: Color(0xFF667eea),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _NotificationToggleInfo {
  final String key;
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final bool value;

  _NotificationToggleInfo({
    required this.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.value,
  });
}