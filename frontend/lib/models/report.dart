enum ReportPeriod { week, month, year, custom }

class CategoryBreakdown {
  final String category;
  final double amount;
  final double percentage;
  final int transactionCount;

  CategoryBreakdown({
    required this.category,
    required this.amount,
    required this.percentage,
    required this.transactionCount,
  });

  factory CategoryBreakdown.fromJson(Map<String, dynamic> json) {
    return CategoryBreakdown(
      category: json['category'],
      amount: json['amount'].toDouble(),
      percentage: json['percentage'].toDouble(),
      transactionCount: json['transaction_count'],
    );
  }
}

class GoalProgressReport {
  final String goalId;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final double progressPercentage;
  final String status;

  GoalProgressReport({
    required this.goalId,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    required this.progressPercentage,
    required this.status,
  });

  factory GoalProgressReport.fromJson(Map<String, dynamic> json) {
    return GoalProgressReport(
      goalId: json['goal_id'],
      name: json['name'],
      targetAmount: json['target_amount'].toDouble(),
      currentAmount: json['current_amount'].toDouble(),
      progressPercentage: json['progress_percentage'].toDouble(),
      status: json['status'],
    );
  }
}

class FinancialReport {
  final ReportPeriod period;
  final DateTime startDate;
  final DateTime endDate;
  final double totalInflow;
  final double totalOutflow;
  final double netBalance;
  final List<CategoryBreakdown> inflowByCategory;
  final List<CategoryBreakdown> outflowByCategory;
  final List<GoalProgressReport> goals;
  final double totalAllocatedToGoals;
  final int totalTransactions;
  final int inflowCount;
  final int outflowCount;
  final String? topIncomeCategory;
  final String? topExpenseCategory;
  final double averageDailyInflow;
  final double averageDailyOutflow;
  final DateTime generatedAt;

  FinancialReport({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.totalInflow,
    required this.totalOutflow,
    required this.netBalance,
    required this.inflowByCategory,
    required this.outflowByCategory,
    required this.goals,
    required this.totalAllocatedToGoals,
    required this.totalTransactions,
    required this.inflowCount,
    required this.outflowCount,
    this.topIncomeCategory,
    this.topExpenseCategory,
    required this.averageDailyInflow,
    required this.averageDailyOutflow,
    required this.generatedAt,
  });

  factory FinancialReport.fromJson(Map<String, dynamic> json) {
    return FinancialReport(
      period: ReportPeriod.values.firstWhere((e) => e.name == json['period']),
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      totalInflow: json['total_inflow'].toDouble(),
      totalOutflow: json['total_outflow'].toDouble(),
      netBalance: json['net_balance'].toDouble(),
      inflowByCategory: (json['inflow_by_category'] as List)
          .map((e) => CategoryBreakdown.fromJson(e))
          .toList(),
      outflowByCategory: (json['outflow_by_category'] as List)
          .map((e) => CategoryBreakdown.fromJson(e))
          .toList(),
      goals: (json['goals'] as List)
          .map((e) => GoalProgressReport.fromJson(e))
          .toList(),
      totalAllocatedToGoals: json['total_allocated_to_goals'].toDouble(),
      totalTransactions: json['total_transactions'],
      inflowCount: json['inflow_count'],
      outflowCount: json['outflow_count'],
      topIncomeCategory: json['top_income_category'],
      topExpenseCategory: json['top_expense_category'],
      averageDailyInflow: json['average_daily_inflow'].toDouble(),
      averageDailyOutflow: json['average_daily_outflow'].toDouble(),
      generatedAt: DateTime.parse(json['generated_at']),
    );
  }
}