import 'package:frontend/utils/money.dart';
import 'package:frontend/utils/date_parsing.dart';
import 'package:frontend/models/user.dart';

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
  final Currency currency;  // NEW

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
    required this.currency,  // NEW
  });

  factory Goal.fromJson(Map<String, dynamic> json) {
    return Goal(
      id: json['id'],
      userId: json['user_id'],
      name: json['name'],
      targetAmount: json['target_amount'].toDouble(),
      currentAmount: json['current_amount'].toDouble(),
      targetDate: parseWallClockOrNull(json['target_date']),
      goalType: GoalType.values.firstWhere((e) => e.name == json['goal_type']),
      status: GoalStatus.values.firstWhere((e) => e.name == json['status']),
      progressPercentage: json['progress_percentage'].toDouble(),
      createdAt: parseInstant(json['created_at']),
      updatedAt: parseInstant(json['updated_at']),
      achievedAt: parseInstantOrNull(json['achieved_at']),
      currency: Currency.fromString(json['currency'] ?? 'usd'),  // NEW
    );
  }
  
  /// An active goal whose (wall-clock) target date is before [now]'s
  /// calendar day. A goal due today is not overdue yet.
  bool isOverdueOn(DateTime now) {
    final due = targetDate;
    if (status != GoalStatus.active || due == null) return false;
    final dueDay = DateTime(due.year, due.month, due.day);
    final today = DateTime(now.year, now.month, now.day);
    return dueDay.isBefore(today);
  }

  bool get isOverdue => isOverdueOn(DateTime.now());

  // NEW - Helper method to display amounts with currency symbol
  String get displayCurrentAmount {
    return formatMoney(currentAmount, currency);
  }
  
  String get displayTargetAmount {
    return formatMoney(targetAmount, currency);
  }
  
  String get displayRemainingAmount {
    return formatMoney((targetAmount - currentAmount), currency);
  }
}

class GoalsSummary {
  final int totalGoals;
  final int activeGoals;
  final int achievedGoals;
  final double totalAllocated;
  final double totalTarget;
  final double overallProgress;
  final Currency? currency;  // NEW

  GoalsSummary({
    required this.totalGoals,
    required this.activeGoals,
    required this.achievedGoals,
    required this.totalAllocated,
    required this.totalTarget,
    required this.overallProgress,
    this.currency,  // NEW
  });

  factory GoalsSummary.fromJson(Map<String, dynamic> json) {
    return GoalsSummary(
      totalGoals: json['total_goals'],
      activeGoals: json['active_goals'],
      achievedGoals: json['achieved_goals'],
      totalAllocated: json['total_allocated'].toDouble(),
      totalTarget: json['total_target'].toDouble(),
      overallProgress: json['overall_progress'].toDouble(),
      currency: json['currency'] != null ? Currency.fromString(json['currency']) : null,  // NEW
    );
  }
  
  // NEW - Helper methods for display
  String displayTotalAllocated(Currency currency) {
    return formatMoney(totalAllocated, currency);
  }
  
  String displayTotalTarget(Currency currency) {
    return formatMoney(totalTarget, currency);
  }
}


// ADD these new classes to goal.dart

class CurrencySummary {
  final Currency currency;
  final int activeGoals;
  final int achievedGoals;
  final double totalAllocated;
  final double totalTarget;
  final double overallProgress;

  CurrencySummary({
    required this.currency,
    required this.activeGoals,
    required this.achievedGoals,
    required this.totalAllocated,
    required this.totalTarget,
    required this.overallProgress,
  });

  factory CurrencySummary.fromJson(Map<String, dynamic> json) {
    return CurrencySummary(
      currency: Currency.fromString(json['currency']),
      activeGoals: json['active_goals'],
      achievedGoals: json['achieved_goals'],
      totalAllocated: json['total_allocated'].toDouble(),
      totalTarget: json['total_target'].toDouble(),
      overallProgress: json['overall_progress'].toDouble(),
    );
  }

  String get displayTotalAllocated {
    return formatMoney(totalAllocated, currency);
  }

  String get displayTotalTarget {
    return formatMoney(totalTarget, currency);
  }
}

class MultiCurrencyGoalsSummary {
  final int totalGoals;
  final int activeGoals;
  final int achievedGoals;
  final List<CurrencySummary> currencySummaries;

  MultiCurrencyGoalsSummary({
    required this.totalGoals,
    required this.activeGoals,
    required this.achievedGoals,
    required this.currencySummaries,
  });

  factory MultiCurrencyGoalsSummary.fromJson(Map<String, dynamic> json) {
    return MultiCurrencyGoalsSummary(
      totalGoals: json['total_goals'],
      activeGoals: json['active_goals'],
      achievedGoals: json['achieved_goals'],
      currencySummaries: (json['currency_summaries'] as List)
          .map((e) => CurrencySummary.fromJson(e))
          .toList(),
    );
  }

  // Get summary for a specific currency
  CurrencySummary? getSummaryForCurrency(Currency currency) {
    try {
      return currencySummaries.firstWhere((s) => s.currency == currency);
    } catch (e) {
      return null;
    }
  }

  // Get all currencies that have goals
  List<Currency> get currencies {
    return currencySummaries.map((s) => s.currency).toList();
  }
}