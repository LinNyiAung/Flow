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
  recurring_transaction_created,   // ADD
  recurring_transaction_ended,     // ADD
  recurring_transaction_disabled,  // ADD
}

class AppNotification {
  final String id;
  final String userId;
  final NotificationType type;
  final String title;
  final String message;
  final String? goalId;
  final String? goalName;
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
    createdAt: DateTime.parse(json['created_at'] + 'Z').toLocal(), // Add 'Z' to mark as UTC
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
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
    };
  }
}