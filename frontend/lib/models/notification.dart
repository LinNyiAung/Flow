enum NotificationType {
  goal_progress,
  goal_milestone,
  goal_approaching_date,
  goal_achieved,
  budget_started,
  budget_ending_soon,
  budget_threshold,
  budget_exceeded,
  budget_auto_created,
  budget_now_active,
  large_transaction,
  unusual_spending,
  payment_reminder,
  recurring_transaction_created,
  recurring_transaction_ended,
  recurring_transaction_disabled,
  weekly_insights_generated,
}

class AppNotification {
  final String id;
  final String userId;
  final NotificationType type;
  final String title;
  final String message;
  final String? goalId;
  final String? goalName;
  final String? currency;  // NEW - add currency field
  final DateTime createdAt;
  final bool isRead;

  AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    this.goalId,
    this.goalName,
    this.currency,  // NEW
    required this.createdAt,
    required this.isRead,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'],
      userId: json['user_id'],
      type: NotificationType.values.firstWhere(
        (e) => e.name == json['type'],
      ),
      title: json['title'],
      message: json['message'],
      goalId: json['goal_id'],
      goalName: json['goal_name'],
      currency: json['currency'],  // NEW
      createdAt: DateTime.parse(json['created_at'] + 'Z').toLocal(),
      isRead: json['is_read'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type.name,
      'title': title,
      'message': message,
      'goal_id': goalId,
      'goal_name': goalName,
      'currency': currency,  // NEW
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
    };
  }
  
  // NEW - Helper method to get currency symbol
  String getCurrencySymbol() {
    if (currency == 'mmk') {
      return 'K';
    }
    return '\$';
  }
  
  // NEW - Helper method to check if notification is currency-related
  bool isCurrencyRelated() {
    return currency != null && (
      type == NotificationType.goal_progress ||
      type == NotificationType.goal_milestone ||
      type == NotificationType.goal_approaching_date ||
      type == NotificationType.goal_achieved ||
      type == NotificationType.budget_started ||
      type == NotificationType.budget_threshold ||
      type == NotificationType.budget_exceeded ||
      type == NotificationType.budget_auto_created ||
      type == NotificationType.budget_now_active ||
      type == NotificationType.large_transaction ||
      type == NotificationType.unusual_spending ||
      type == NotificationType.payment_reminder
    );
  }
}