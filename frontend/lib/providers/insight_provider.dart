import 'package:flutter/material.dart';
import '../models/insight.dart';
import '../services/api_service.dart';

class InsightProvider with ChangeNotifier {
  Insight? _insight;
  bool _isLoading = false;
  String? _error;

  Insight? get insight => _insight;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  // Fetch insights (cached or generate new)
  Future<void> fetchInsights() async {
    _setLoading(true);
    _setError(null);

    try {
      _insight = await ApiService.getInsights();
      _setLoading(false);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
    }
  }

  // Force regenerate insights
  Future<bool> regenerateInsights() async {
    _setLoading(true);
    _setError(null);

    try {
      _insight = await ApiService.regenerateInsights();
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  // Clear cached insights
  Future<bool> clearInsights() async {
    _setError(null);

    try {
      await ApiService.deleteInsights();
      _insight = null;
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}