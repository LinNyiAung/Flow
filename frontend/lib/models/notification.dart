enum NotificationType {
  goal_progress,
  goal_milestone,
  goal_approaching_date,
  goal_achieved,
  budget_started,          // ADD THIS
  budget_ending_soon,      // ADD THIS
  budget_threshold,        // ADD THIS
  budget_exceeded,         // ADD THIS
  budget_auto_created,     // ADD THIS
  budget_now_active,       // ADD THIS
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
      createdAt: DateTime.parse(json['created_at']),
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