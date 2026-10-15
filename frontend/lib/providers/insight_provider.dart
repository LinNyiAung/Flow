import 'package:flutter/material.dart';
import 'package:frontend/models/chat.dart';
import '../models/insight.dart';
import '../services/api_service.dart';

class InsightProvider with ChangeNotifier {
  Insight? _insight;
  bool _isLoading = false;
  String? _error;
  int? _errorStatusCode;
  String? _actionError;
  int? _actionErrorStatusCode;
  String _currentLanguage = 'en';
  AIProvider _aiProvider = AIProvider.gemini;
  String _insightType = 'weekly';

  /// Bumped on [reset] and on every new load; responses that arrive for an
  /// older generation (previous user / previous type) are discarded.
  int _generation = 0;

  Insight? get insight => _insight;
  bool get isLoading => _isLoading;

  /// Error of the last load that left no insight to show (fetch, or a
  /// regenerate when nothing was loaded yet). When set, [insight] is null.
  String? get error => _error;

  /// HTTP status of [error] (null for timeouts / network errors).
  int? get errorStatusCode => _errorStatusCode;

  /// Error of the last secondary action (regenerate, translation, clear)
  /// that did not invalidate the currently shown insight.
  String? get actionError => _actionError;

  /// HTTP status of [actionError] (null for timeouts / network errors).
  int? get actionErrorStatusCode => _actionErrorStatusCode;

  static int? _statusOf(Object e) => e is ApiException ? e.statusCode : null;

  void _clearErrors() {
    _error = null;
    _errorStatusCode = null;
    _actionError = null;
    _actionErrorStatusCode = null;
  }
  String get currentLanguage => _currentLanguage;
  AIProvider get aiProvider => _aiProvider;
  String get insightType => _insightType;

  /// Clears all per-user state (called on logout / user switch).
  void reset() {
    _generation++;
    _insight = null;
    _isLoading = false;
    _clearErrors();
    _currentLanguage = 'en';
    _aiProvider = AIProvider.gemini;
    _insightType = 'weekly';
    notifyListeners();
  }

  void setInsightType(String type) {
    if (type != _insightType) {
      _generation++;
      _insightType = type;
      _insight = null; // never show the other period's insight
      _clearErrors();
      notifyListeners();
    }
  }

  void setAIProvider(AIProvider provider) {
    if (provider != _aiProvider) {
      _generation++;
      _aiProvider = provider;
      _insight = null;
      _clearErrors();
      notifyListeners();
    }
  }

  void setLanguage(String language) {
    if (language != _currentLanguage) {
      _currentLanguage = language;
      notifyListeners();
    }
  }

  static String _clean(Object e) => e.toString().replaceAll('Exception: ', '');

  Future<void> fetchInsights({String? language, String? insightType}) async {
    final lang = language ?? _currentLanguage;
    final type = insightType ?? _insightType;
    final gen = ++_generation;

    // Start from a clean slate so a failed load can never leave a previous
    // (possibly other type's) insight on screen.
    _insight = null;
    _clearErrors();
    _insightType = type;
    _isLoading = true;
    notifyListeners();

    try {
      final result = await ApiService.getInsights(
        language: lang,
        aiProvider: _aiProvider,
        insightType: type,
      );
      if (gen != _generation) return;
      _insight = result;
      _currentLanguage = lang;
    } catch (e) {
      if (gen != _generation) return;
      _insight = null;
      _error = _clean(e);
      _errorStatusCode = _statusOf(e);
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Regenerates the insight. On failure the currently shown insight (if
  /// any) is kept and the failure is reported via [actionError]; only when
  /// there is nothing to show is [error] set as well (full-page error).
  Future<bool> regenerateInsights({String? language, String? insightType}) async {
    final lang = language ?? _currentLanguage;
    final type = insightType ?? _insightType;
    final gen = ++_generation;

    _clearErrors();
    _isLoading = true;
    notifyListeners();

    try {
      final result = await ApiService.regenerateInsights(
        language: lang,
        aiProvider: _aiProvider,
        insightType: type,
      );
      if (gen != _generation) return false;
      _insight = result;
      _currentLanguage = lang;
      _insightType = type;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (gen != _generation) return false;
      _actionError = _clean(e);
      _actionErrorStatusCode = _statusOf(e);
      if (_insight == null) {
        _error = _actionError;
        _errorStatusCode = _actionErrorStatusCode;
      }
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Translates the CURRENT insight type (weekly or monthly) to Myanmar and
  /// refetches that same type.
  Future<bool> translateToMyanmar() async {
    final type = _insightType;
    final gen = ++_generation;
    _actionError = null;
    _actionErrorStatusCode = null;
    _isLoading = true;
    notifyListeners();

    try {
      await ApiService.translateInsightsToMyanmar(
        aiProvider: _aiProvider,
        insightType: type,
      );
      final result = await ApiService.getInsights(
        language: 'mm',
        aiProvider: _aiProvider,
        insightType: type,
      );
      if (gen != _generation) return false;
      _insight = result;
      _currentLanguage = 'mm';
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (gen != _generation) return false;
      // Translation failed: keep the insight that is already shown.
      _actionError = _clean(e);
      _actionErrorStatusCode = _statusOf(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> clearInsights() async {
    _error = null;
    _errorStatusCode = null;
    try {
      await ApiService.deleteInsights(aiProvider: _aiProvider);
      _generation++;
      _insight = null;
      notifyListeners();
      return true;
    } catch (e) {
      _actionError = _clean(e);
      _actionErrorStatusCode = _statusOf(e);
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _clearErrors();
    notifyListeners();
  }

  String? getContentForLanguage() {
    if (_insight == null) return null;

    if (_currentLanguage == 'mm' && _insight!.contentMm != null) {
      return _insight!.contentMm;
    }

    return _insight!.content;
  }
}
