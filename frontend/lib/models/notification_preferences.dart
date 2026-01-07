class NotificationPreferences {
  // Goal notifications
  final bool goalProgress;
  final bool goalMilestone;
  final bool goalApproachingDate;
  final bool goalAchieved;
  
  // Budget notifications
  final bool budgetStarted;
  final bool budgetEndingSoon;
  final bool budgetThreshold;
  final bool budgetExceeded;
  final bool budgetAutoCreated;
  final bool budgetNowActive;
  
  // Transaction notifications
  final bool largeTransaction;
  final bool unusualSpending;
  final bool paymentReminder;
  final bool recurringTransactionCreated;
  final bool recurringTransactionEnded;
  final bool recurringTransactionDisabled;

  // Insight notifications
  final bool weeklyInsightsGenerated;

  NotificationPreferences({
    this.goalProgress = true,
    this.goalMilestone = true,
    this.goalApproachingDate = true,
    this.goalAchieved = true,
    this.budgetStarted = true,
    this.budgetEndingSoon = true,
    this.budgetThreshold = true,
    this.budgetExceeded = true,
    this.budgetAutoCreated = true,
    this.budgetNowActive = true,
    this.largeTransaction = true,
    this.unusualSpending = true,
    this.paymentReminder = true,
    this.recurringTransactionCreated = true,
    this.recurringTransactionEnded = true,
    this.recurringTransactionDisabled = true,
    this.weeklyInsightsGenerated = true,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      goalProgress: json['goal_progress'] ?? true,
      goalMilestone: json['goal_milestone'] ?? true,
      goalApproachingDate: json['goal_approaching_date'] ?? true,
      goalAchieved: json['goal_achieved'] ?? true,
      budgetStarted: json['budget_started'] ?? true,
      budgetEndingSoon: json['budget_ending_soon'] ?? true,
      budgetThreshold: json['budget_threshold'] ?? true,
      budgetExceeded: json['budget_exceeded'] ?? true,
      budgetAutoCreated: json['budget_auto_created'] ?? true,
      budgetNowActive: json['budget_now_active'] ?? true,
      largeTransaction: json['large_transaction'] ?? true,
      unusualSpending: json['unusual_spending'] ?? true,
      paymentReminder: json['payment_reminder'] ?? true,
      recurringTransactionCreated: json['recurring_transaction_created'] ?? true,
      recurringTransactionEnded: json['recurring_transaction_ended'] ?? true,
      recurringTransactionDisabled: json['recurring_transaction_disabled'] ?? true,
      weeklyInsightsGenerated: json['weekly_insights_generated'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'goal_progress': goalProgress,
      'goal_milestone': goalMilestone,
      'goal_approaching_date': goalApproachingDate,
      'goal_achieved': goalAchieved,
      'budget_started': budgetStarted,
      'budget_ending_soon': budgetEndingSoon,
      'budget_threshold': budgetThreshold,
      'budget_exceeded': budgetExceeded,
      'budget_auto_created': budgetAutoCreated,
      'budget_now_active': budgetNowActive,
      'large_transaction': largeTransaction,
      'unusual_spending': unusualSpending,
      'payment_reminder': paymentReminder,
      'recurring_transaction_created': recurringTransactionCreated,
      'recurring_transaction_ended': recurringTransactionEnded,
      'recurring_transaction_disabled': recurringTransactionDisabled,
      'weekly_insights_generated': weeklyInsightsGenerated,
    };
  }

  NotificationPreferences copyWith({
    bool? goalProgress,
    bool? goalMilestone,
    bool? goalApproachingDate,
    bool? goalAchieved,
    bool? budgetStarted,
    bool? budgetEndingSoon,
    bool? budgetThreshold,
    bool? budgetExceeded,
    bool? budgetAutoCreated,
    bool? budgetNowActive,
    bool? largeTransaction,
    bool? unusualSpending,
    bool? paymentReminder,
    bool? recurringTransactionCreated,
    bool? recurringTransactionEnded,
    bool? recurringTransactionDisabled,
    bool? weeklyInsightsGenerated,
  }) {
    return NotificationPreferences(
      goalProgress: goalProgress ?? this.goalProgress,
      goalMilestone: goalMilestone ?? this.goalMilestone,
      goalApproachingDate: goalApproachingDate ?? this.goalApproachingDate,
      goalAchieved: goalAchieved ?? this.goalAchieved,
      budgetStarted: budgetStarted ?? this.budgetStarted,
      budgetEndingSoon: budgetEndingSoon ?? this.budgetEndingSoon,
      budgetThreshold: budgetThreshold ?? this.budgetThreshold,
      budgetExceeded: budgetExceeded ?? this.budgetExceeded,
      budgetAutoCreated: budgetAutoCreated ?? this.budgetAutoCreated,
      budgetNowActive: budgetNowActive ?? this.budgetNowActive,
      largeTransaction: largeTransaction ?? this.largeTransaction,
      unusualSpending: unusualSpending ?? this.unusualSpending,
      paymentReminder: paymentReminder ?? this.paymentReminder,
      recurringTransactionCreated: recurringTransactionCreated ?? this.recurringTransactionCreated,
      recurringTransactionEnded: recurringTransactionEnded ?? this.recurringTransactionEnded,
      recurringTransactionDisabled: recurringTransactionDisabled ?? this.recurringTransactionDisabled,
      weeklyInsightsGenerated: weeklyInsightsGenerated ?? this.weeklyInsightsGenerated,
    );
  }
}

class NotificationPreferencesResponse {
  final String userId;
  final NotificationPreferences preferences;
  final DateTime updatedAt;

  NotificationPreferencesResponse({
    required this.userId,
    required this.preferences,
    required this.updatedAt,
  });

  factory NotificationPreferencesResponse.fromJson(Map<String, dynamic> json) {
    return NotificationPreferencesResponse(
      userId: json['user_id'],
      preferences: NotificationPreferences.fromJson(json['preferences']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}