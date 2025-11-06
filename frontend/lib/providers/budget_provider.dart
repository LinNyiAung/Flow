import 'package:flutter/material.dart';
import '../models/budget.dart';
import '../services/api_service.dart';

class BudgetProvider with ChangeNotifier {
  List<Budget> _budgets = [];
  BudgetSummary? _summary;
  bool _isLoading = false;
  String? _error;

  List<Budget> get budgets => _budgets;
  BudgetSummary? get summary => _summary;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<Budget> get activeBudgets => _budgets.where((b) => b.isActive).toList();
  List<Budget> get completedBudgets => _budgets.where((b) => b.status == BudgetStatus.completed).toList();
  List<Budget> get exceededBudgets => _budgets.where((b) => b.status == BudgetStatus.exceeded).toList();

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  Future<AIBudgetSuggestion?> getAISuggestions({
    required BudgetPeriod period,
    required DateTime startDate,
    DateTime? endDate,
    List<String>? includeCategories,
    int analysisMonths = 3,
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
      );

      _budgets.insert(0, budget);
      await fetchSummary();
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
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      _budgets = await ApiService.getBudgets(
        activeOnly: activeOnly,
        period: period,
      );
      _setLoading(false);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
    }
  }

  Future<void> fetchSummary() async {
    try {
      _summary = await ApiService.getBudgetsSummary();
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
      );

      final index = _budgets.indexWhere((b) => b.id == budgetId);
      if (index != -1) {
        _budgets[index] = updatedBudget;
      }

      await fetchSummary();
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
      await ApiService.deleteBudget(budgetId);
      _budgets.removeWhere((b) => b.id == budgetId);
      await fetchSummary();
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
      await fetchBudgets();
    } catch (e) {
      print("Error refreshing budget: $e");
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}