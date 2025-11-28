import 'package:frontend/models/user.dart';  // NEW: import Currency

enum BudgetPeriod { weekly, monthly, yearly, custom }

enum BudgetStatus { active, completed, exceeded, upcoming }

class CategoryBudget {
  final String mainCategory;
  final double allocatedAmount;
  final double spentAmount;
  final double percentageUsed;
  final bool isExceeded;

  CategoryBudget({
    required this.mainCategory,
    required this.allocatedAmount,
    required this.spentAmount,
    required this.percentageUsed,
    required this.isExceeded,
  });

  factory CategoryBudget.fromJson(Map<String, dynamic> json) {
    return CategoryBudget(
      mainCategory: json['main_category'],
      allocatedAmount: json['allocated_amount'].toDouble(),
      spentAmount: json['spent_amount'].toDouble(),
      percentageUsed: json['percentage_used'].toDouble(),
      isExceeded: json['is_exceeded'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'main_category': mainCategory,
      'allocated_amount': allocatedAmount,
      'spent_amount': spentAmount,
      'percentage_used': percentageUsed,
      'is_exceeded': isExceeded,
    };
  }
}

class Budget {
  final String id;
  final String userId;
  final String name;
  final BudgetPeriod period;
  final DateTime startDate;
  final DateTime endDate;
  final List<CategoryBudget> categoryBudgets;
  final double totalBudget;
  final double totalSpent;
  final double remainingBudget;
  final double percentageUsed;
  final BudgetStatus status;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool autoCreateEnabled;
  final bool autoCreateWithAi;
  final String? parentBudgetId;
  final Currency currency;  // NEW

  Budget({
    required this.id,
    required this.userId,
    required this.name,
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.categoryBudgets,
    required this.totalBudget,
    required this.totalSpent,
    required this.remainingBudget,
    required this.percentageUsed,
    required this.status,
    this.description,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.autoCreateEnabled = false,
    this.autoCreateWithAi = false,
    this.parentBudgetId,
    required this.currency,  // NEW
  });

  bool get isUpcoming {
    final now = DateTime.now().toUtc();
    return now.isBefore(startDate.toUtc());
  }
  
  bool get isAutoCreated => parentBudgetId != null;

  // NEW: Display amount with currency symbol
  String get displayTotalBudget {
    return '${currency.symbol}${totalBudget.toStringAsFixed(2)}';
  }

  String get displayTotalSpent {
    return '${currency.symbol}${totalSpent.toStringAsFixed(2)}';
  }

  String get displayRemainingBudget {
    return '${currency.symbol}${remainingBudget.toStringAsFixed(2)}';
  }

  factory Budget.fromJson(Map<String, dynamic> json) {
    return Budget(
      id: json['id'],
      userId: json['user_id'],
      name: json['name'],
      period: BudgetPeriod.values.firstWhere((e) => e.name == json['period']),
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      categoryBudgets: (json['category_budgets'] as List)
          .map((cat) => CategoryBudget.fromJson(cat))
          .toList(),
      totalBudget: json['total_budget'].toDouble(),
      totalSpent: json['total_spent'].toDouble(),
      remainingBudget: json['remaining_budget'].toDouble(),
      percentageUsed: json['percentage_used'].toDouble(),
      status: BudgetStatus.values.firstWhere((e) => e.name == json['status']),
      description: json['description'],
      isActive: json['is_active'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      autoCreateEnabled: json['auto_create_enabled'] ?? false,
      autoCreateWithAi: json['auto_create_with_ai'] ?? false,
      parentBudgetId: json['parent_budget_id'],
      currency: Currency.fromString(json['currency'] ?? 'usd'),  // NEW with fallback
    );
  }
}

class BudgetSummary {
  final int totalBudgets;
  final int activeBudgets;
  final int completedBudgets;
  final int exceededBudgets;
  final int upcomingBudgets;
  final double totalAllocated;
  final double totalSpent;
  final double overallRemaining;
  final Currency currency;  // NEW

  BudgetSummary({
    required this.totalBudgets,
    required this.activeBudgets,
    required this.completedBudgets,
    required this.exceededBudgets,
    required this.upcomingBudgets,
    required this.totalAllocated,
    required this.totalSpent,
    required this.overallRemaining,
    required this.currency,  // NEW
  });

  // NEW: Display methods
  String get displayTotalAllocated {
    return '${currency.symbol}${totalAllocated.toStringAsFixed(2)}';
  }

  String get displayTotalSpent {
    return '${currency.symbol}${totalSpent.toStringAsFixed(2)}';
  }

  String get displayOverallRemaining {
    return '${currency.symbol}${overallRemaining.toStringAsFixed(2)}';
  }

  factory BudgetSummary.fromJson(Map<String, dynamic> json) {
    return BudgetSummary(
      totalBudgets: json['total_budgets'],
      activeBudgets: json['active_budgets'],
      completedBudgets: json['completed_budgets'],
      exceededBudgets: json['exceeded_budgets'],
      upcomingBudgets: json['upcoming_budgets'] ?? 0,
      totalAllocated: json['total_allocated'].toDouble(),
      totalSpent: json['total_spent'].toDouble(),
      overallRemaining: json['overall_remaining'].toDouble(),
      currency: Currency.fromString(json['currency'] ?? 'usd'),  // NEW with fallback
    );
  }
}

class AIBudgetSuggestion {
  final String suggestedName;
  final BudgetPeriod period;
  final DateTime startDate;
  final DateTime endDate;
  final List<CategoryBudget> categoryBudgets;
  final double totalBudget;
  final String reasoning;
  final double dataConfidence;
  final List<String> warnings;
  final Map<String, dynamic> analysisSummary;
  final Currency currency;  // NEW

  AIBudgetSuggestion({
    required this.suggestedName,
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.categoryBudgets,
    required this.totalBudget,
    required this.reasoning,
    required this.dataConfidence,
    required this.warnings,
    required this.analysisSummary,
    required this.currency,  // NEW
  });

  factory AIBudgetSuggestion.fromJson(Map<String, dynamic> json) {
    return AIBudgetSuggestion(
      suggestedName: json['suggested_name'],
      period: BudgetPeriod.values.firstWhere((e) => e.name == json['period']),
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      categoryBudgets: (json['category_budgets'] as List)
          .map((cat) => CategoryBudget.fromJson(cat))
          .toList(),
      totalBudget: json['total_budget'].toDouble(),
      reasoning: json['reasoning'],
      dataConfidence: json['data_confidence'].toDouble(),
      warnings: List<String>.from(json['warnings']),
      analysisSummary: json['analysis_summary'],
      currency: Currency.fromString(json['currency'] ?? 'usd'),  // NEW with fallback
    );
  }
}


class CurrencyBudgetSummary {
  final Currency currency;
  final int totalBudgets;
  final int activeBudgets;
  final int completedBudgets;
  final int exceededBudgets;
  final int upcomingBudgets;
  final double totalAllocated;
  final double totalSpent;
  final double overallRemaining;

  CurrencyBudgetSummary({
    required this.currency,
    required this.totalBudgets,
    required this.activeBudgets,
    required this.completedBudgets,
    required this.exceededBudgets,
    required this.upcomingBudgets,
    required this.totalAllocated,
    required this.totalSpent,
    required this.overallRemaining,
  });

  factory CurrencyBudgetSummary.fromJson(Map<String, dynamic> json) {
    return CurrencyBudgetSummary(
      currency: Currency.fromString(json['currency']),
      totalBudgets: json['total_budgets'],
      activeBudgets: json['active_budgets'],
      completedBudgets: json['completed_budgets'],
      exceededBudgets: json['exceeded_budgets'],
      upcomingBudgets: json['upcoming_budgets'],
      totalAllocated: json['total_allocated'].toDouble(),
      totalSpent: json['total_spent'].toDouble(),
      overallRemaining: json['overall_remaining'].toDouble(),
    );
  }

  String get displayTotalAllocated {
    return '${currency.symbol}${totalAllocated.toStringAsFixed(2)}';
  }

  String get displayTotalSpent {
    return '${currency.symbol}${totalSpent.toStringAsFixed(2)}';
  }

  String get displayOverallRemaining {
    return '${currency.symbol}${overallRemaining.toStringAsFixed(2)}';
  }

  double get percentageUsed {
    return totalAllocated > 0 ? (totalSpent / totalAllocated * 100) : 0;
  }
}

class MultiCurrencyBudgetSummary {
  final int totalBudgets;
  final int activeBudgets;
  final int completedBudgets;
  final int exceededBudgets;
  final int upcomingBudgets;
  final List<CurrencyBudgetSummary> currencySummaries;

  MultiCurrencyBudgetSummary({
    required this.totalBudgets,
    required this.activeBudgets,
    required this.completedBudgets,
    required this.exceededBudgets,
    required this.upcomingBudgets,
    required this.currencySummaries,
  });

  factory MultiCurrencyBudgetSummary.fromJson(Map<String, dynamic> json) {
    return MultiCurrencyBudgetSummary(
      totalBudgets: json['total_budgets'],
      activeBudgets: json['active_budgets'],
      completedBudgets: json['completed_budgets'],
      exceededBudgets: json['exceeded_budgets'],
      upcomingBudgets: json['upcoming_budgets'],
      currencySummaries: (json['currency_summaries'] as List)
          .map((e) => CurrencyBudgetSummary.fromJson(e))
          .toList(),
    );
  }

  CurrencyBudgetSummary? getSummaryForCurrency(Currency currency) {
    try {
      return currencySummaries.firstWhere((s) => s.currency == currency);
    } catch (e) {
      return null;
    }
  }

  List<Currency> get currencies {
    return currencySummaries.map((s) => s.currency).toList();
  }
}