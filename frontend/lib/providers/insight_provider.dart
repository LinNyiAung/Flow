import 'package:flutter/material.dart';
import 'package:frontend/models/chat.dart';
import '../models/insight.dart';
import '../services/api_service.dart';

class InsightProvider with ChangeNotifier {
  Insight? _insight;
  bool _isLoading = false;
  String? _error;
  String _currentLanguage = 'en'; // NEW: Track current language
  AIProvider _aiProvider = AIProvider.openai; // NEW

  Insight? get insight => _insight;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get currentLanguage => _currentLanguage; // NEW
  AIProvider get aiProvider => _aiProvider; // NEW

  // NEW: Set AI provider
  void setAIProvider(AIProvider provider) {
    if (provider != _aiProvider) {
      _aiProvider = provider;
      _insight = null; // Clear current insights when switching
      notifyListeners();
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  // NEW: Set language preference
  void setLanguage(String language) {
    if (language != _currentLanguage) {
      _currentLanguage = language;
      notifyListeners();
    }
  }

  // Fetch insights with language support
  Future<void> fetchInsights({String? language}) async {
    _setLoading(true);
    _setError(null);

    final lang = language ?? _currentLanguage;

    try {
      _insight = await ApiService.getInsights(
        language: lang,
        aiProvider: _aiProvider, // NEW
      );
      _currentLanguage = lang;
      _setLoading(false);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
    }
  }

  // Force regenerate insights with language support
  Future<bool> regenerateInsights({String? language}) async {
    _setLoading(true);
    _setError(null);

    final lang = language ?? _currentLanguage;

    try {
      _insight = await ApiService.regenerateInsights(
        language: lang,
        aiProvider: _aiProvider, // NEW
      );
      _currentLanguage = lang;
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  // NEW: Translate existing insights to Myanmar
  Future<bool> translateToMyanmar() async {
    _setLoading(true);
    _setError(null);

    try {
      await ApiService.translateInsightsToMyanmar(
        aiProvider: _aiProvider, // NEW
      );
      // Fetch updated insights
      _insight = await ApiService.getInsights(
        language: 'mm',
        aiProvider: _aiProvider, // NEW
      );
      _currentLanguage = 'mm';
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  Future<bool> clearInsights() async {
    _setError(null);

    try {
      await ApiService.deleteInsights(aiProvider: _aiProvider); // NEW
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

  // NEW: Get content based on current language
  String? getContentForLanguage() {
    if (_insight == null) return null;

    if (_currentLanguage == 'mm' && _insight!.contentMm != null) {
      return _insight!.contentMm;
    }

    return _insight!.content;
  }
}
