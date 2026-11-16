import 'package:frontend/utils/date_parsing.dart';

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
  monthly_insights_generated,
  system_broadcast,  // NEW
  admin_announcement,  // NEW
  subscription_expired,
  // ignore: constant_identifier_names
  trial_ending_soon,
  // ignore: constant_identifier_names
  trial_ends_today,
  // A paying user's plan (with an end date) ends within 3 days / within 24 hours.
  // ignore: constant_identifier_names
  plan_ending_soon,
  // ignore: constant_identifier_names
  plan_ends_today,
  // An admin put the user on Plus or Pro.
  // ignore: constant_identifier_names
  plan_activated,
  // An admin closed the user's upgrade request without changing the plan.
  // ignore: constant_identifier_names
  upgrade_request_declined,
  // A custom insight finished; `subject_id` is the report's id.
  // ignore: constant_identifier_names
  custom_insight_ready,
  // A custom insight could not be made (or was refused).
  // ignore: constant_identifier_names
  custom_insight_failed,
  // You were invited to a family; `subject_id` is the invite's id, `goal_name` the family's name.
  // ignore: constant_identifier_names
  family_invite,
  // Someone joined your family (sent to its admins); `subject_id` is the family's id.
  // ignore: constant_identifier_names
  family_invite_accepted,
  // An admin removed you from the family.
  // ignore: constant_identifier_names
  family_removed,
  // The owner deleted their account, so the family is yours now.
  // ignore: constant_identifier_names
  family_owner,
}

extension FamilyNotificationType on NotificationType {
  /// About the person's family itself (not about either book's money).
  bool get isFamilyNotice =>
      this == NotificationType.family_invite ||
      this == NotificationType.family_invite_accepted ||
      this == NotificationType.family_removed ||
      this == NotificationType.family_owner;
}

extension PlanNotificationType on NotificationType {
  /// About the user's plan: shown with the plan icon and colour, and opens
  /// the Upgrade screen when tapped.
  bool get isPlanNotice =>
      this == NotificationType.subscription_expired ||
      this == NotificationType.trial_ending_soon ||
      this == NotificationType.trial_ends_today ||
      this == NotificationType.plan_ending_soon ||
      this == NotificationType.plan_ends_today ||
      this == NotificationType.plan_activated ||
      this == NotificationType.upgrade_request_declined;
}

/// True when a notification of this type (its wire name, as in a push's data
/// or a stored notification) changes what the plan screens show (the new
/// plan, or a request that is no longer pending), so the app reloads the plan
/// when one arrives or is opened.
bool notificationRefreshesPlan(String? typeName) =>
    typeName == NotificationType.plan_activated.name ||
    typeName == NotificationType.upgrade_request_declined.name;

/// True when a notice of this type (its wire name) is about one book's money
/// (a budget, a goal, entries, insights): it is opened in the book it belongs
/// to, the family's when it carries the family marker, the person's own
/// otherwise (see `openInBook`).
bool notificationBelongsToBook(String? typeName) {
  if (typeName == null) return false;
  if (typeName.startsWith('budget_') || typeName.startsWith('goal_')) return true;
  const others = {
    'large_transaction',
    'unusual_spending',
    'payment_reminder',
    'recurring_transaction_created',
    'recurring_transaction_ended',
    'recurring_transaction_disabled',
    'weekly_insights_generated',
    'monthly_insights_generated',
    'custom_insight_ready',
    'custom_insight_failed',
  };
  return others.contains(typeName);
}

/// True when tapping a notice (or its push) of this type opens a screen
/// through `NotificationOpener`: one book's money, or the family itself (an
/// invitation, a new member, the ownership). Plan notices open the Upgrade
/// screen from the notifications list only.
bool notificationOpensSomething(String? typeName) =>
    notificationBelongsToBook(typeName) ||
    typeName == NotificationType.family_invite.name ||
    typeName == NotificationType.family_invite_accepted.name ||
    typeName == NotificationType.family_owner.name;

class AppNotification {
  final String id;
  final String userId;
  final NotificationType type;
  final String title;
  final String message;
  final String? subjectId;
  final String? goalName;
  final String? currency;  // NEW - add currency field
  final DateTime createdAt;
  final bool isRead;

  /// `extra.book`: `family` for a notice that belongs to the family book (open
  /// it in Family mode); null for the person's own (or for no book at all).
  final String? book;

  AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    this.subjectId,
    this.goalName,
    this.currency,  // NEW
    required this.createdAt,
    required this.isRead,
    this.book,
  });

  /// The notice belongs to the family book.
  bool get isFamilyBook => book == 'family';

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final extra = json['extra'];
    final book = extra is Map ? extra['book'] : null;
    return AppNotification(
      id: json['id'],
      userId: json['user_id'],
      type: NotificationType.values.firstWhere(
        (e) => e.name == json['type'],
        // Newer backend types must not break the whole notifications list.
        orElse: () => NotificationType.system_broadcast,
      ),
      title: json['title'],
      message: json['message'],
      subjectId: json['subject_id'],
      goalName: json['goal_name'],
      currency: json['currency'],  // NEW
      createdAt: parseInstant(json['created_at']),
      isRead: json['is_read'],
      book: book is String ? book : null,
    );
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      userId: userId,
      type: type,
      title: title,
      message: message,
      subjectId: subjectId,
      goalName: goalName,
      currency: currency,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      book: book,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type.name,
      'title': title,
      'message': message,
      'subject_id': subjectId,
      'goal_name': goalName,
      'currency': currency,  // NEW
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
      if (book != null) 'extra': {'book': book},
    };
  }
  
  // NEW - Helper method to get currency symbol
  String getCurrencySymbol() {
    if (currency == 'mmk') {
      return 'K';
    } else if (currency == 'thb') {
      return '฿';
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