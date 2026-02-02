import 'package:flutter/material.dart';
import 'package:frontend/models/feedback.dart';
import '../services/api_service.dart';

class FeedbackProvider with ChangeNotifier {
  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<bool> submitFeedback({
    required FeedbackCategory category,
    required String message,
    int? rating,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final feedback = FeedbackCreate(
        category: category,
        message: message,
        rating: rating,
      );

      await ApiService.submitFeedback(feedback);
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }
}