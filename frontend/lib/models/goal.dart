enum GoalType { savings, debt_reduction, large_purchase }

enum GoalStatus { active, achieved }

class Goal {
  final String id;
  final String userId;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final DateTime? targetDate;
  final GoalType goalType;
  final GoalStatus status;
  final double progressPercentage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? achievedAt;

  Goal({
    required this.id,
    required this.userId,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    this.targetDate,
    required this.goalType,
    required this.status,
    required this.progressPercentage,
    required this.createdAt,
    required this.updatedAt,
    this.achievedAt,
  });

  factory Goal.fromJson(Map<String, dynamic> json) {
    return Goal(
      id: json['id'],
      userId: json['user_id'],
      name: json['name'],
      targetAmount: json['target_amount'].toDouble(),
      currentAmount: json['current_amount'].toDouble(),
      targetDate: json['target_date'] != null ? DateTime.parse(json['target_date']) : null,
      goalType: GoalType.values.firstWhere((e) => e.name == json['goal_type']),
      status: GoalStatus.values.firstWhere((e) => e.name == json['status']),
      progressPercentage: json['progress_percentage'].toDouble(),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      achievedAt: json['achieved_at'] != null ? DateTime.parse(json['achieved_at']) : null,
    );
  }
}

class GoalsSummary {
  final int totalGoals;
  final int activeGoals;
  final int achievedGoals;
  final double totalAllocated;
  final double totalTarget;
  final double overallProgress;

  GoalsSummary({
    required this.totalGoals,
    required this.activeGoals,
    required this.achievedGoals,
    required this.totalAllocated,
    required this.totalTarget,
    required this.overallProgress,
  });

  factory GoalsSummary.fromJson(Map<String, dynamic> json) {
    return GoalsSummary(
      totalGoals: json['total_goals'],
      activeGoals: json['active_goals'],
      achievedGoals: json['achieved_goals'],
      totalAllocated: json['total_allocated'].toDouble(),
      totalTarget: json['total_target'].toDouble(),
      overallProgress: json['overall_progress'].toDouble(),
    );
  }
}