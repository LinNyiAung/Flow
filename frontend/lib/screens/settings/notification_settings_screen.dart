import 'package:flutter/material.dart';
import 'package:frontend/models/notification.dart';
import 'package:frontend/models/notification_preferences.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/localization_service.dart';
import '../../services/notification_service.dart';

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
        const SnackBar(content: Text('Failed to update preference')),
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
      monthlyInsightsGenerated: key == 'monthly_insights_generated' ? value : _preferences!.monthlyInsightsGenerated,
    );
  }

  Future<void> _toggleNotifications(bool value) async {
    final localizations = AppLocalizations.of(context);
    if (value) {
      final granted = await _notificationService.requestPermissions();
      if (granted) {
        setState(() => _notificationsEnabled = true);
        await _loadPreferences();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.notificationsEnabled)),
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
              child: Icon(Icons.settings_rounded, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(localizations.notificationSettings)),
          ],
        ),
        content: Text(localizations.changeNotificationSettingsDes),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.dialogCancel),
          ),
          FilledButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: Text(localizations.openSettings),
          ),
        ],
      ),
    );
  }

  Future<void> _testNotification() async {
    final localizations = AppLocalizations.of(context);
    await _notificationService.showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: localizations.testNotification,
      body: localizations.testNotificationDes,
      type: NotificationType.goal_progress,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(localizations.testNotificationMsg)),
    );
  }

  Future<void> _resetToDefaults() async {
    final localizations = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.resetToDefaults),
        content: Text(localizations.enableAllNotificationTypes),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.dialogCancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ApiService.resetNotificationPreferences();
                await _loadPreferences();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(localizations.notificationPreferencesReset)),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(localizations.failedToResetPreferences)),
                );
              }
            },
            child: Text(localizations.reset),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.notificationSettings),
        actions: [
          if (_notificationsEnabled && _preferences != null)
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded),
              onPressed: _resetToDefaults,
              tooltip: localizations.resetToDefaultsWQ,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Master Toggle Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.notifications_active_rounded, color: scheme.onPrimaryContainer, size: 24),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  localizations.pushNotifications,
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  localizations.receiveUpdatesAboutFinances,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer.withValues(alpha: 0.75)),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _notificationsEnabled,
                            onChanged: _toggleNotifications,
                          ),
                        ],
                      ),

                      if (_notificationsEnabled) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: Material(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _testNotification,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                child: Center(
                                  child: Text(
                                    localizations.sendTestNotification,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                if (_notificationsEnabled && _preferences != null) ...[
                  const SizedBox(height: 20),

                  // Info Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.infoContainerFor(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_rounded, color: AppTheme.infoFor(context), size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            localizations.customizeNotificationsReceive,
                            style: TextStyle(fontSize: 13, color: AppTheme.infoFor(context)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Text(
                      localizations.notificationTypes,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.primary),
                    ),
                  ),

                  // Goal Notifications Section
                  _buildNotificationSection(
                    title: localizations.goals,
                    icon: Icons.flag_rounded,
                    notifications: [
                      _NotificationToggleInfo(
                        key: 'goal_progress',
                        icon: Icons.trending_up_rounded,
                        color: scheme.primary,
                        title: localizations.progressUpdates,
                        description: localizations.notifiedMilestones,
                        value: _preferences!.goalProgress,
                      ),
                      _NotificationToggleInfo(
                        key: 'goal_milestone',
                        icon: Icons.star_rounded,
                        color: AppTheme.starFor(context),
                        title: localizations.milestoneReached,
                        description: localizations.thousandSavedTowardsGoal,
                        value: _preferences!.goalMilestone,
                      ),
                      _NotificationToggleInfo(
                        key: 'goal_approaching_date',
                        icon: Icons.event_rounded,
                        color: AppTheme.infoFor(context),
                        title: localizations.deadlineApproaching,
                        description: localizations.reminders,
                        value: _preferences!.goalApproachingDate,
                      ),
                      _NotificationToggleInfo(
                        key: 'goal_achieved',
                        icon: Icons.emoji_events_rounded,
                        color: scheme.tertiary,
                        title: localizations.goalAchieved,
                        description: localizations.celebrate,
                        value: _preferences!.goalAchieved,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Budget Notifications Section
                  _buildNotificationSection(
                    title: localizations.budgets,
                    icon: Icons.account_balance_wallet_rounded,
                    notifications: [
                      _NotificationToggleInfo(
                        key: 'budget_started',
                        icon: Icons.play_circle_filled_rounded,
                        color: scheme.primary,
                        title: localizations.budgetStarted,
                        description: localizations.whenNewBudgetBegins,
                        value: _preferences!.budgetStarted,
                      ),
                      _NotificationToggleInfo(
                        key: 'budget_ending_soon',
                        icon: Icons.access_time_rounded,
                        color: scheme.tertiary,
                        title: localizations.periodEndingSoon,
                        description: localizations.reminderBudgets,
                        value: _preferences!.budgetEndingSoon,
                      ),
                      _NotificationToggleInfo(
                        key: 'budget_threshold',
                        icon: Icons.warning_amber_rounded,
                        color: scheme.tertiary,
                        title: localizations.budgetThreshold,
                        description: localizations.alertBudget,
                        value: _preferences!.budgetThreshold,
                      ),
                      _NotificationToggleInfo(
                        key: 'budget_exceeded',
                        icon: Icons.error_rounded,
                        color: scheme.error,
                        title: localizations.budgetExceeded,
                        description: localizations.whenOverBudgetLimit,
                        value: _preferences!.budgetExceeded,
                      ),
                      _NotificationToggleInfo(
                        key: 'budget_auto_created',
                        icon: Icons.autorenew_rounded,
                        color: scheme.primary,
                        title: localizations.autoCreatedBudget,
                        description: localizations.budgetCreatedAutomatically,
                        value: _preferences!.budgetAutoCreated,
                      ),
                      _NotificationToggleInfo(
                        key: 'budget_now_active',
                        icon: Icons.check_circle_rounded,
                        color: scheme.primary,
                        title: localizations.budgetNowActive,
                        description: localizations.whenBudgetBecomesActive,
                        value: _preferences!.budgetNowActive,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Insights Notifications Section
                  _buildNotificationSection(
                    title: localizations.aiInsights,
                    icon: Icons.insights_rounded,
                    notifications: [
                      _NotificationToggleInfo(
                        key: 'weekly_insights_generated',
                        icon: Icons.insights_rounded,
                        color: scheme.primary,
                        title: localizations.weeklyInsights,
                        description: localizations.whenWeeklyInsightsReady,
                        value: _preferences!.weeklyInsightsGenerated,
                      ),
                      _NotificationToggleInfo(
                        // NEW
                        key: 'monthly_insights_generated',
                        icon: Icons.calendar_month_rounded,
                        color: AppTheme.infoFor(context),
                        title: 'Monthly Insights',
                        description: 'When your monthly insights are ready',
                        value: _preferences!.monthlyInsightsGenerated,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Transaction Notifications Section
                  _buildNotificationSection(
                    title: localizations.transactions,
                    icon: Icons.receipt_long_rounded,
                    notifications: [
                      _NotificationToggleInfo(
                        key: 'large_transaction',
                        icon: Icons.payments_rounded,
                        color: scheme.tertiary,
                        title: localizations.largeTransaction,
                        description: localizations.alertsLargeExpenses,
                        value: _preferences!.largeTransaction,
                      ),
                      _NotificationToggleInfo(
                        key: 'unusual_spending',
                        icon: Icons.trending_up_rounded,
                        color: scheme.error,
                        title: localizations.unusualSpending,
                        description: localizations.whenSpendingPatternsChange,
                        value: _preferences!.unusualSpending,
                      ),
                      _NotificationToggleInfo(
                        key: 'payment_reminder',
                        icon: Icons.notifications_active_rounded,
                        color: AppTheme.infoFor(context),
                        title: localizations.paymentReminders,
                        description: localizations.upcomingPayments,
                        value: _preferences!.paymentReminder,
                      ),
                      _NotificationToggleInfo(
                        key: 'recurring_transaction_created',
                        icon: Icons.repeat_rounded,
                        color: scheme.primary,
                        title: localizations.recurringCreated,
                        description: localizations.whenRecurringTransactionsCreated,
                        value: _preferences!.recurringTransactionCreated,
                      ),
                      _NotificationToggleInfo(
                        key: 'recurring_transaction_ended',
                        icon: Icons.repeat_one_rounded,
                        color: scheme.onSurfaceVariant,
                        title: localizations.recurringEnded,
                        description: localizations.whenRecurringEnds,
                        value: _preferences!.recurringTransactionEnded,
                      ),
                      _NotificationToggleInfo(
                        key: 'recurring_transaction_disabled',
                        icon: Icons.repeat_on_rounded,
                        color: scheme.tertiary,
                        title: localizations.recurringDisabled,
                        description: localizations.whenRecurrenceDisabled,
                        value: _preferences!.recurringTransactionDisabled,
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),
                ],
              ],
            ),
    );
  }

  Widget _buildNotificationSection({
    required String title,
    required IconData icon,
    required List<_NotificationToggleInfo> notifications,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < notifications.length; i++) ...[
                if (i > 0) const Divider(),
                _buildNotificationToggleItem(notif: notifications[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationToggleItem({required _NotificationToggleInfo notif}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: notif.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(notif.icon, color: notif.color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notif.title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  notif.description,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: notif.value,
            onChanged: (value) => _updatePreference(notif.key, value),
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
