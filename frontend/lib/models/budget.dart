import 'package:frontend/utils/money.dart';
import 'package:frontend/utils/date_parsing.dart';
import 'package:frontend/models/user.dart';

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

  /// [startDate] is a wall-clock date parsed as a local DateTime, so it is
  /// compared with the local now.
  bool get isUpcoming => DateTime.now().isBefore(startDate);

  /// Whether this budget feeds the insights health score at [now]: an
  /// enabled budget that is running (active), over its cap (exceeded), or
  /// whose window contains [now] (whatever status the server reported).
  /// Budgets whose window already ended never count.
  bool countsTowardHealthScore(DateTime now) {
    if (!isActive || now.isAfter(endDate)) return false;
    if (status == BudgetStatus.active || status == BudgetStatus.exceeded) {
      return true;
    }
    return !now.isBefore(startDate);
  }

  bool get isAutoCreated => parentBudgetId != null;

  // NEW: Display amount with currency symbol
  String get displayTotalBudget {
    return formatMoney(totalBudget, currency);
  }

  String get displayTotalSpent {
    return formatMoney(totalSpent, currency);
  }

  String get displayRemainingBudget {
    return formatMoney(remainingBudget, currency);
  }

  factory Budget.fromJson(Map<String, dynamic> json) {
    return Budget(
      id: json['id'],
      userId: json['user_id'],
      name: json['name'],
      period: BudgetPeriod.values.firstWhere((e) => e.name == json['period']),
      startDate: parseWallClock(json['start_date']),
      endDate: parseWallClock(json['end_date']),
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
      createdAt: parseInstant(json['created_at']),
      updatedAt: parseInstant(json['updated_at']),
      autoCreateEnabled: json['auto_create_enabled'] ?? false,
      autoCreateWithAi: json['auto_create_with_ai'] ?? false,
      parentBudgetId: json['parent_budget_id'],
      currency: Currency.fromString(json['currency'] ?? 'usd'),  // NEW with fallback
    );
  }
}

/// Which cap a budget is over, for wording its status. The backend reports a
/// budget as `exceeded` both when its total is over and when only one of its
/// categories is; those read very differently ("16% used" yet "EXCEEDED").
///
/// "Over" here is at the currency's display precision ([isOverCap]): whole
/// kyat for MMK, cents otherwise. A kyat budget K0.40 over shows as within
/// cap ("Remaining K0"), never "Over by K0".
extension BudgetOverState on Budget {
  /// Total spent above the total budget by an amount that shows.
  bool get isTotalOver => isOverCap(totalSpent, totalBudget, currency);

  /// The categories over their own cap by an amount that shows.
  List<CategoryBudget> get categoriesOver =>
      categoryBudgets.where((c) => c.isOverIn(currency)).toList();

  /// Exceeded only because of its categories: the total is still within cap.
  bool get onlyCategoriesOver =>
      status == BudgetStatus.exceeded && !isTotalOver && categoriesOver.isNotEmpty;

  /// The status to show (badge, banner): `exceeded` reads as `active` when
  /// nothing is over by an amount that shows.
  BudgetStatus get displayStatus =>
      status == BudgetStatus.exceeded && !isTotalOver && categoriesOver.isEmpty ? BudgetStatus.active : status;
}

extension CategoryOverState on CategoryBudget {
  /// Spent above this category's cap by an amount that shows in [currency].
  bool isOverIn(Currency currency) => isOverCap(spentAmount, allocatedAmount, currency);
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
    return formatMoney(totalAllocated, currency);
  }

  String get displayTotalSpent {
    return formatMoney(totalSpent, currency);
  }

  String get displayOverallRemaining {
    return formatMoney(overallRemaining, currency);
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
      startDate: parseWallClock(json['start_date']),
      endDate: parseWallClock(json['end_date']),
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
    return formatMoney(totalAllocated, currency);
  }

  String get displayTotalSpent {
    return formatMoney(totalSpent, currency);
  }

  String get displayOverallRemaining {
    return formatMoney(overallRemaining, currency);
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