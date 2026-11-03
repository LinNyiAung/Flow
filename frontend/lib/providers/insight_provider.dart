import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/insight.dart';
import '../services/api_service.dart';

/// Loads the latest insight ([ApiService.getInsights]).
typedef InsightFetcher = Future<Insight> Function({
  required String language,
  required String insightType,
});

class InsightProvider with ChangeNotifier {
  /// Shared-preferences key of the English / မြန်မာ choice.
  static const String languagePrefsKey = 'insight_language';

  /// Where insights come from; the real API unless a test supplies its own.
  final InsightFetcher _fetcher;

  InsightProvider({InsightFetcher? fetcher})
      : _fetcher = fetcher ?? _apiFetcher;

  static Future<Insight> _apiFetcher({
    required String language,
    required String insightType,
  }) =>
      ApiService.getInsights(language: language, insightType: insightType);

  Insight? _insight;
  bool _isLoading = false;
  String? _error;
  int? _errorStatusCode;
  String? _actionError;
  int? _actionErrorStatusCode;
  String _currentLanguage = 'en';
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

  /// Set when [error] / [actionError] came from the plan refusing the request
  /// (locked, used up, monthly AI limit) rather than from a failure.
  PlanLimitException? _errorPlanLimit;
  PlanLimitException? _actionPlanLimit;
  PlanLimitException? get errorPlanLimit => _errorPlanLimit;
  PlanLimitException? get actionPlanLimit => _actionPlanLimit;

  /// Set while Myanmar was asked for and the server refused to translate it
  /// (a limit) but still sent the English insight: the screen shows it in
  /// English, keeps the English / မြန်မာ toggle and a short note with
  /// [TranslationUnavailable.message]. Not an error, and the remembered
  /// language choice is not touched, so the next load asks for Myanmar again.
  TranslationUnavailable? _translationNote;
  TranslationUnavailable? get translationNote => _translationNote;

  /// Shows [result], asked for in [requested]. A plan without translation, or
  /// a refused translation, leaves English on screen.
  void _show(Insight result, String requested) {
    _insight = result;
    final refused = requested == 'mm' &&
        result.contentMm == null &&
        !result.translationLocked &&
        result.translationUnavailable != null;
    _translationNote = refused ? result.translationUnavailable : null;
    _currentLanguage = result.translationLocked || refused ? 'en' : requested;
  }

  static int? _statusOf(Object e) => e is ApiException ? e.statusCode : null;

  static PlanLimitException? _limitOf(Object e) =>
      e is PlanLimitException ? e : null;

  void _clearErrors() {
    _error = null;
    _errorStatusCode = null;
    _errorPlanLimit = null;
    _actionError = null;
    _actionErrorStatusCode = null;
    _actionPlanLimit = null;
  }
  String get currentLanguage => _currentLanguage;
  String get insightType => _insightType;

  /// Clears all per-user state (called on logout / user switch).
  void reset() {
    _generation++;
    _insight = null;
    _isLoading = false;
    _clearErrors();
    _translationNote = null;
    _currentLanguage = 'en';
    _preferredLanguage = null; // read again from the device for the next user
    _insightType = 'weekly';
    notifyListeners();
  }

  void setInsightType(String type) {
    if (type != _insightType) {
      _generation++;
      _insightType = type;
      _insight = null; // never show the other period's insight
      _translationNote = null;
      _clearErrors();
      notifyListeners();
    }
  }

  /// The language the user last chose with the Insights toggle ('en' | 'mm'),
  /// remembered on the device; null until they choose one.
  String? _preferredLanguage;

  /// Reads the remembered language choice.
  Future<void> loadPreferredLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(languagePrefsKey);
      _preferredLanguage = saved == 'en' || saved == 'mm' ? saved : null;
    } catch (e) {
      debugPrint('Could not read the insight language: $e');
    }
  }

  Future<void> _rememberLanguage(String language) async {
    _preferredLanguage = language;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(languagePrefsKey, language);
    } catch (e) {
      debugPrint('Could not save the insight language: $e');
    }
  }

  /// The language to ask the server for: the remembered choice, starting on
  /// the app language ([appLanguage], 'en' | 'mm'). A plan without
  /// translation (Free) always gets English.
  String wantedLanguage({required bool translationAvailable, required String appLanguage}) =>
      translationAvailable ? (_preferredLanguage ?? appLanguage) : 'en';

  /// Shows the insight in [language] ('en' | 'mm'). Myanmar that the insight
  /// does not carry yet is fetched from the server, which translates once and
  /// stores it; flipping back and forth afterwards costs nothing. On failure
  /// the insight on screen is kept and the failure is in [actionError] /
  /// [actionPlanLimit]. Returns true when [language] is now shown.
  Future<bool> showLanguage(String language) async {
    if (language == 'en' && _translationNote != null) {
      // Chose English on purpose: the "Myanmar unavailable" note no longer applies.
      _translationNote = null;
      notifyListeners();
    }
    if (language == _currentLanguage) return true;
    final current = _insight;
    if (language == 'en' || (current != null && current.contentMm != null)) {
      _translationNote = null;
      _currentLanguage = language;
      notifyListeners();
      unawaited(_rememberLanguage(language));
      return true;
    }

    final type = _insightType;
    final gen = ++_generation;
    _actionError = null;
    _actionErrorStatusCode = null;
    _actionPlanLimit = null;
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _fetcher(language: language, insightType: type);
      if (gen != _generation) return false;
      // A plan without translation answers in English and says so; so does a
      // refused translation (the note under the toggle says why).
      _show(result, language);
      final shown = result.contentMm == null ? 'en' : _currentLanguage;
      _currentLanguage = shown;
      _isLoading = false;
      notifyListeners();
      if (shown == language) unawaited(_rememberLanguage(language));
      return shown == language;
    } catch (e) {
      if (gen != _generation) return false;
      // Translation failed: keep the insight that is already shown.
      _actionError = _clean(e);
      _actionErrorStatusCode = _statusOf(e);
      _actionPlanLimit = _limitOf(e);
      _isLoading = false;
      notifyListeners();
      return false;
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
    _translationNote = null;
    _clearErrors();
    _insightType = type;
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _fetcher(language: lang, insightType: type);
      if (gen != _generation) return;
      _show(result, lang);
    } catch (e) {
      if (gen != _generation) return;
      _insight = null;
      _error = _clean(e);
      _errorStatusCode = _statusOf(e);
      _errorPlanLimit = _limitOf(e);
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
        insightType: type,
      );
      if (gen != _generation) return false;
      _show(result, lang);
      _insightType = type;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (gen != _generation) return false;
      _actionError = _clean(e);
      _actionErrorStatusCode = _statusOf(e);
      _actionPlanLimit = _limitOf(e);
      if (_insight == null) {
        _error = _actionError;
        _errorStatusCode = _actionErrorStatusCode;
        _errorPlanLimit = _actionPlanLimit;
      }
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> clearInsights() async {
    _error = null;
    _errorStatusCode = null;
    try {
      await ApiService.deleteInsights();
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
