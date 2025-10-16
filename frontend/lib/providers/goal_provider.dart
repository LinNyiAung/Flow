import 'package:flutter/material.dart';
import '../models/goal.dart';
import '../services/api_service.dart';

class GoalProvider with ChangeNotifier {
  List<Goal> _goals = [];
  GoalsSummary? _summary;
  bool _isLoading = false;
  String? _error;

  List<Goal> get goals => _goals;
  GoalsSummary? get summary => _summary;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<Goal> get activeGoals => _goals.where((g) => g.status == GoalStatus.active).toList();
  List<Goal> get achievedGoals => _goals.where((g) => g.status == GoalStatus.achieved).toList();

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  Future<bool> createGoal({
    required String name,
    required double targetAmount,
    DateTime? targetDate,
    required GoalType goalType,
    double initialContribution = 0.0,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final goal = await ApiService.createGoal(
        name: name,
        targetAmount: targetAmount,
        targetDate: targetDate,
        goalType: goalType,
        initialContribution: initialContribution,
      );

      _goals.insert(0, goal);
      await fetchSummary();
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  Future<void> fetchGoals({GoalStatus? statusFilter}) async {
    _setLoading(true);
    _setError(null);

    try {
      _goals = await ApiService.getGoals(statusFilter: statusFilter);
      _setLoading(false);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
    }
  }

  Future<void> fetchSummary() async {
    try {
      _summary = await ApiService.getGoalsSummary();
      notifyListeners();
    } catch (e) {
      print("Error fetching goals summary: $e");
    }
  }

  Future<Goal?> getGoal(String goalId) async {
    try {
      return await ApiService.getGoal(goalId);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      return null;
    }
  }

  Future<bool> updateGoal({
    required String goalId,
    String? name,
    double? targetAmount,
    DateTime? targetDate,
    GoalType? goalType,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final updatedGoal = await ApiService.updateGoal(
        goalId: goalId,
        name: name,
        targetAmount: targetAmount,
        targetDate: targetDate,
        goalType: goalType,
      );

      final index = _goals.indexWhere((g) => g.id == goalId);
      if (index != -1) {
        _goals[index] = updatedGoal;
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

  Future<bool> contributeToGoal({
    required String goalId,
    required double amount,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final updatedGoal = await ApiService.contributeToGoal(
        goalId: goalId,
        amount: amount,
      );

      final index = _goals.indexWhere((g) => g.id == goalId);
      if (index != -1) {
        _goals[index] = updatedGoal;
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

  Future<bool> deleteGoal(String goalId) async {
    _setLoading(true);
    _setError(null);

    try {
      await ApiService.deleteGoal(goalId);
      _goals.removeWhere((g) => g.id == goalId);
      await fetchSummary();
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}