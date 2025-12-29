import 'package:frontend/models/user.dart';

enum ReportPeriod { week, month, year, custom }

class CategoryBreakdown {
  final String category;
  final String mainCategory;  // NEW - Add this field
  final double amount;
  final double percentage;
  final int transactionCount;

  CategoryBreakdown({
    required this.category,
    required this.mainCategory,  // NEW
    required this.amount,
    required this.percentage,
    required this.transactionCount,
  });

  factory CategoryBreakdown.fromJson(Map<String, dynamic> json) {
    return CategoryBreakdown(
      category: json['category'],
      mainCategory: json['main_category'],  // NEW
      amount: json['amount'].toDouble(),
      percentage: json['percentage'].toDouble(),
      transactionCount: json['transaction_count'],
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
  final Currency currency;  // NEW

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
    required this.currency,  // NEW
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
      currency: Currency.fromString(json['currency'] ?? 'usd'),  // NEW
    );
  }
  
  // NEW - Helper method to format amount with currency
  String formatAmount(double amount) {
    return '${currency.symbol}${amount.toStringAsFixed(2)}';
  }
}

class GoalProgressReport {
  final String goalId;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final double progressPercentage;
  final String status;
  final Currency currency;  // NEW

  GoalProgressReport({
    required this.goalId,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    required this.progressPercentage,
    required this.status,
    required this.currency,  // NEW
  });

  factory GoalProgressReport.fromJson(Map<String, dynamic> json) {
    return GoalProgressReport(
      goalId: json['goal_id'],
      name: json['name'],
      targetAmount: json['target_amount'].toDouble(),
      currentAmount: json['current_amount'].toDouble(),
      progressPercentage: json['progress_percentage'].toDouble(),
      status: json['status'],
      currency: Currency.fromString(json['currency'] ?? 'usd'),  // NEW
    );
  }
}


class CurrencyReport {
  final Currency currency;
  final double totalInflow;
  final double totalOutflow;
  final double netBalance;
  final List<CategoryBreakdown> inflowByCategory;
  final List<CategoryBreakdown> outflowByCategory;
  final int totalTransactions;
  final int inflowCount;
  final int outflowCount;
  final double averageDailyInflow;
  final double averageDailyOutflow;

  CurrencyReport({
    required this.currency,
    required this.totalInflow,
    required this.totalOutflow,
    required this.netBalance,
    required this.inflowByCategory,
    required this.outflowByCategory,
    required this.totalTransactions,
    required this.inflowCount,
    required this.outflowCount,
    required this.averageDailyInflow,
    required this.averageDailyOutflow,
  });

  factory CurrencyReport.fromJson(Map<String, dynamic> json) {
    return CurrencyReport(
      currency: Currency.fromString(json['currency']),
      totalInflow: json['total_inflow'].toDouble(),
      totalOutflow: json['total_outflow'].toDouble(),
      netBalance: json['net_balance'].toDouble(),
      inflowByCategory: (json['inflow_by_category'] as List)
          .map((e) => CategoryBreakdown.fromJson(e))
          .toList(),
      outflowByCategory: (json['outflow_by_category'] as List)
          .map((e) => CategoryBreakdown.fromJson(e))
          .toList(),
      totalTransactions: json['total_transactions'],
      inflowCount: json['inflow_count'],
      outflowCount: json['outflow_count'],
      averageDailyInflow: json['average_daily_inflow'].toDouble(),
      averageDailyOutflow: json['average_daily_outflow'].toDouble(),
    );
  }
}

class MultiCurrencyFinancialReport {
  final ReportPeriod period;
  final DateTime startDate;
  final DateTime endDate;
  final List<CurrencyReport> currencyReports;
  final List<GoalProgressReport> goals;
  final int totalTransactions;
  final DateTime generatedAt;

  MultiCurrencyFinancialReport({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.currencyReports,
    required this.goals,
    required this.totalTransactions,
    required this.generatedAt,
  });

  factory MultiCurrencyFinancialReport.fromJson(Map<String, dynamic> json) {
    return MultiCurrencyFinancialReport(
      period: ReportPeriod.values.firstWhere((e) => e.name == json['period']),
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      currencyReports: (json['currency_reports'] as List)
          .map((e) => CurrencyReport.fromJson(e))
          .toList(),
      goals: (json['goals'] as List)
          .map((e) => GoalProgressReport.fromJson(e))
          .toList(),
      totalTransactions: json['total_transactions'],
      generatedAt: DateTime.parse(json['generated_at']),
    );
  }
}