import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';  // NEW: import Currency
import '../models/budget.dart';
import '../services/api_service.dart';

class BudgetProvider with ChangeNotifier {
  List<Budget> _budgets = [];
  BudgetSummary? _summary;
  bool _isLoading = false;
  String? _error;
  Currency? _selectedCurrency;  // NEW: track selected currency for filtering
  MultiCurrencyBudgetSummary? _multiCurrencySummary;

  List<Budget> get budgets => _budgets;
  BudgetSummary? get summary => _summary;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Currency? get selectedCurrency => _selectedCurrency;  // NEW
  MultiCurrencyBudgetSummary? get multiCurrencySummary => _multiCurrencySummary;

  List<Budget> get activeBudgets => _budgets
      .where((b) => b.isActive && b.status == BudgetStatus.active)
      .toList();
  List<Budget> get upcomingBudgets => _budgets
      .where((b) => b.isUpcoming || b.status == BudgetStatus.upcoming)
      .toList();
  List<Budget> get completedBudgets =>
      _budgets.where((b) => b.status == BudgetStatus.completed).toList();
  List<Budget> get exceededBudgets =>
      _budgets.where((b) => b.status == BudgetStatus.exceeded).toList();

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  // NEW: Set selected currency for filtering
  void setSelectedCurrency(Currency currency) {
    _selectedCurrency = currency;
    notifyListeners();
  }

  Future<void> fetchMultiCurrencySummary() async {
  try {
    _multiCurrencySummary = await ApiService.getMultiCurrencyBudgetsSummary();
    notifyListeners();
  } catch (e) {
    print("Error fetching multi-currency budgets summary: $e");
  }
}

  Future<AIBudgetSuggestion?> getAISuggestions({
    required BudgetPeriod period,
    required DateTime startDate,
    DateTime? endDate,
    List<String>? includeCategories,
    int analysisMonths = 3,
    String? userContext,
    required Currency currency,  // NEW - make it required
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final suggestion = await ApiService.getAIBudgetSuggestions(
        period: period,
        startDate: startDate,
        endDate: endDate,
        includeCategories: includeCategories,
        analysisMonths: analysisMonths,
        userContext: userContext,
        currency: currency,  // NEW
      );

      _setLoading(false);
      return suggestion;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return null;
    }
  }

  Future<bool> createBudget({
    required String name,
    required BudgetPeriod period,
    required DateTime startDate,
    DateTime? endDate,
    required List<CategoryBudget> categoryBudgets,
    required double totalBudget,
    String? description,
    bool autoCreateEnabled = false,
    bool autoCreateWithAi = false,
    required Currency currency,  // NEW - make it required
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final budget = await ApiService.createBudget(
        name: name,
        period: period,
        startDate: startDate,
        endDate: endDate,
        categoryBudgets: categoryBudgets,
        totalBudget: totalBudget,
        description: description,
        autoCreateEnabled: autoCreateEnabled,
        autoCreateWithAi: autoCreateWithAi,
        currency: currency,  // NEW
      );

      _budgets.insert(0, budget);
      await fetchSummary(currency: currency);  // NEW: fetch summary for this currency
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  Future<void> fetchBudgets({
    bool activeOnly = false,
    BudgetPeriod? period,
    Currency? currency,  // NEW - optional filter
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      _budgets = await ApiService.getBudgets(
        activeOnly: activeOnly,
        period: period,
        currency: currency,  // NEW
      );
      _setLoading(false);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
    }
  }

  Future<void> fetchSummary({Currency? currency}) async {  // NEW: add currency parameter
    try {
      _summary = await ApiService.getBudgetsSummary(currency: currency);
      notifyListeners();
    } catch (e) {
      print("Error fetching budget summary: $e");
    }
  }

  Future<Budget?> getBudget(String budgetId) async {
    try {
      return await ApiService.getBudget(budgetId);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      return null;
    }
  }

  Future<bool> updateBudget({
    required String budgetId,
    String? name,
    List<CategoryBudget>? categoryBudgets,
    double? totalBudget,
    String? description,
    bool? autoCreateEnabled,
    bool? autoCreateWithAi,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final updatedBudget = await ApiService.updateBudget(
        budgetId: budgetId,
        name: name,
        categoryBudgets: categoryBudgets,
        totalBudget: totalBudget,
        description: description,
        autoCreateEnabled: autoCreateEnabled,
        autoCreateWithAi: autoCreateWithAi,
      );

      final index = _budgets.indexWhere((b) => b.id == budgetId);
      if (index != -1) {
        _budgets[index] = updatedBudget;
      }

      await fetchSummary(currency: updatedBudget.currency);  // NEW: use budget's currency
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  Future<bool> deleteBudget(String budgetId) async {
    _setLoading(true);
    _setError(null);

    try {
      // Get the budget's currency before deleting
      final budget = _budgets.firstWhere((b) => b.id == budgetId);
      final budgetCurrency = budget.currency;
      
      await ApiService.deleteBudget(budgetId);
      _budgets.removeWhere((b) => b.id == budgetId);
      
      await fetchSummary(currency: budgetCurrency);  // NEW: use budget's currency
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  Future<void> refreshBudget(String budgetId) async {
    try {
      await ApiService.refreshBudget(budgetId);
      await fetchBudgets(currency: _selectedCurrency);  // NEW: refresh with selected currency
    } catch (e) {
      print("Error refreshing budget: $e");
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}